-- Plans 3D sur le site : visite 3D d'un programme, ouverte après le formulaire de la fiche programme.
--
-- Appliquée le 27/11/2026 (migration « plans_3d »), sur signal de la session mère, SANS la partie 7
-- (aucune visite enregistrée, aucun fichier déposé). Vérifié après coup : Colombes identique (89ba6291…).
-- Décisions d'Alex (session mère, 27/11/2026) : « Après le formulaire » ; « oui c'est mieux que appelez nous.
-- mets les leads chez moi, et garde les numéros de lots. »
--
-- Ce que crée cette migration (rien n'est retiré, rien n'est effacé) :
--   0. Sauvegarde de la version en ligne de neuf_ville_public dans fonctions_backup_20261127.
--   1. Espace de stockage PRIVÉ « plans3d » (15 Mo par fichier, pages HTML seulement) :
--        plans3d/<clé programme>/immeuble.html  et  plans3d/<clé programme>/<clé lot>.html
--      Aucune règle d'accès : seule la clé de service (edge function plans-3d) lit et dépose.
--   2. neuf_visites_3d : une ligne par fichier visitable (lot_id vide = l'immeuble).
--   3. neuf_3d_jetons : jetons remis par le formulaire (seule leur empreinte est gardée), 30 jours.
--   4. neuf_3d_appels : compteur par jour, contre l'aspiration (40 fichiers par jeton, 60 par adresse).
--   5. neuf_3d_acces(...) et neuf_3d_jeton_creer(...) : réservées à service_role (edge function plans-3d).
--   6. neuf_ville_public : ajoute « visite_3d »: true au programme et « v3d »: true au lot, SEULEMENT
--      quand une visite est enregistrée. Tant que neuf_visites_3d est vide, la réponse est identique
--      octet pour octet à aujourd'hui (aucun risque pour les pages ville ni pour le robot du site).
--
-- Nouveau programme : déposer ses fichiers dans plans3d/<clé programme>/, puis une ligne par fichier
-- dans neuf_visites_3d. Aucun code à toucher.

-- 0. Sauvegarde ------------------------------------------------------------------------------------
create table if not exists public.fonctions_backup_20261127 (
  nom text primary key,
  definition text not null,
  sauve_le timestamptz not null default now()
);
alter table public.fonctions_backup_20261127 enable row level security;
revoke all on public.fonctions_backup_20261127 from public, anon, authenticated;
grant all on public.fonctions_backup_20261127 to service_role;

insert into public.fonctions_backup_20261127 (nom, definition)
select 'neuf_ville_public(text)', pg_get_functiondef('public.neuf_ville_public(text)'::regprocedure)
on conflict (nom) do nothing;

-- 1. Espace de stockage privé ----------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('plans3d', 'plans3d', false, 15728640, array['text/html'])
on conflict (id) do nothing;

-- 2. Visites enregistrées --------------------------------------------------------------------------
create table if not exists public.neuf_visites_3d (
  id           bigint generated always as identity primary key,
  programme_id text not null,              -- pige_programmes.id (jamais montré : le site ne voit que neuf_cle)
  lot_id       text,                       -- pige_lots.id ; vide = la page de l'immeuble
  fichier      text not null unique,       -- chemin dans l'espace plans3d
  actif        boolean not null default true,
  ajoute_le    timestamptz not null default now()
);
create unique index if not exists neuf_visites_3d_un on public.neuf_visites_3d (programme_id, coalesce(lot_id, ''));
create index if not exists neuf_visites_3d_lot on public.neuf_visites_3d (lot_id);

alter table public.neuf_visites_3d enable row level security;
revoke all on public.neuf_visites_3d from public, anon;
grant select on public.neuf_visites_3d to authenticated;
grant all on public.neuf_visites_3d to service_role;

-- 3. Jetons du formulaire --------------------------------------------------------------------------
create table if not exists public.neuf_3d_jetons (
  empreinte  text primary key,             -- sha-256 du jeton ; le jeton lui-même n'est jamais gardé
  contact_id uuid,
  programme  text,                         -- clé publique du programme où le formulaire a été rempli
  cree_le    timestamptz not null default now(),
  expire_le  timestamptz not null default now() + interval '30 days'
);
alter table public.neuf_3d_jetons enable row level security;
revoke all on public.neuf_3d_jetons from public, anon, authenticated;
grant all on public.neuf_3d_jetons to service_role;

-- 4. Compteur contre l'aspiration (une ligne par jeton ou adresse et par jour, sans effacement) -----
create table if not exists public.neuf_3d_appels (
  qui  text not null,                      -- 'j:<empreinte du jeton>' ou 'ip:<empreinte de l'adresse>'
  jour date not null,
  n    integer not null default 0,
  primary key (qui, jour)
);
alter table public.neuf_3d_appels enable row level security;
revoke all on public.neuf_3d_appels from public, anon, authenticated;
grant all on public.neuf_3d_appels to service_role;

-- 5a. Enregistrer un jeton (appelée par plans-3d après la création du lead) -------------------------
create or replace function public.neuf_3d_jeton_creer(p_empreinte text, p_contact uuid, p_programme text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into neuf_3d_jetons (empreinte, contact_id, programme)
  values (p_empreinte, p_contact, p_programme)
  on conflict (empreinte) do nothing;
$$;
revoke all on function public.neuf_3d_jeton_creer(text, uuid, text) from public, anon, authenticated;
grant execute on function public.neuf_3d_jeton_creer(text, uuid, text) to service_role;

-- 5b. Donner le chemin d'un fichier à un visiteur passé par le formulaire --------------------------
-- Réponse : { statut: 'ok', fichier }  |  { statut: 'jeton' } (absent, faux ou expiré : la page montre
-- le formulaire)  |  { statut: 'inconnu' }  |  { statut: 'limite' }.
create or replace function public.neuf_3d_acces(p_programme text, p_lot text, p_empreinte text, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_par_jeton constant integer := 40;
  c_par_ip    constant integer := 60;
  v_jour  date := (now() at time zone 'Europe/Paris')::date;
  v_fich  text;
  v_nj    integer;
  v_ni    integer;
begin
  if p_empreinte is null or not exists (
       select 1 from neuf_3d_jetons where empreinte = p_empreinte and expire_le > now()) then
    return jsonb_build_object('statut', 'jeton');
  end if;

  insert into neuf_3d_appels (qui, jour, n) values ('j:' || p_empreinte, v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_nj;
  insert into neuf_3d_appels (qui, jour, n) values ('ip:' || coalesce(p_ip, 'inconnue'), v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_ni;
  if v_nj > c_par_jeton or v_ni > c_par_ip then
    return jsonb_build_object('statut', 'limite');
  end if;

  select x.fichier into v_fich
    from neuf_visites_3d x
   where x.actif
     and neuf_cle(x.programme_id) = p_programme
     and ((p_lot is null and x.lot_id is null) or (p_lot is not null and x.lot_id is not null and neuf_cle(x.lot_id) = p_lot))
   limit 1;
  if v_fich is null then
    return jsonb_build_object('statut', 'inconnu');
  end if;
  return jsonb_build_object('statut', 'ok', 'fichier', v_fich);
end;
$$;
revoke all on function public.neuf_3d_acces(text, text, text, text) from public, anon, authenticated;
grant execute on function public.neuf_3d_acces(text, text, text, text) to service_role;

-- 6. neuf_ville_public : version en ligne (md5 du corps 6a5f6547…, 20261125_neuf_arrondissements_et_compteurs.sql)
--    + visite_3d / v3d, présents seulement quand une visite est enregistrée.
create or replace function public.neuf_ville_public(p_ville text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with v as (
    select * from neuf_villes where ville = p_ville or slug = p_ville limit 1
  ), actuel as (
    select extract(year from now())::int + extract(quarter from now())::int / 10.0 as cle
  ), lots as (
    select l.programme_id,
           neuf_cle(l.id) as id,
           l.typo, l.pieces, l.surf, l.st as statut,
           case when l.etage ~ '^-?[0-9]+$' then l.etage::int end as etage,
           case when lower(coalesce(l.data->>'annexes', '')) like '%jardin%'   then 'Jardin'
                when lower(coalesce(l.data->>'annexes', '')) like '%terrasse%' then 'Terrasse'
                when lower(coalesce(l.data->>'annexes', '')) like '%loggia%'   then 'Loggia'
                when lower(coalesce(l.data->>'annexes', '')) like '%balcon%'   then 'Balcon'
                when l.ext then 'Extérieur' end as exterieur,
           -- Plans 3D (27/11/2026) : lot visitable en 3D après le formulaire
           exists (select 1 from neuf_visites_3d x where x.lot_id = l.id and x.actif) as v3d
      from pige_lots l
      join pige_programmes p on p.id = l.programme_id
      join v on v.dept = p.dept
       and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
       and (v.cps is null or p.cp = any(v.cps))
     where coalesce(p.source, '') not in ('picking', 'nomandat')
       and l.st in ('libre', 'option')
       and l.type in ('Appartement', 'Maison')
       and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
  ), progs as (
    select p.id, neuf_cle(p.id) as cle, p.nom,
           coalesce(p.source, '') = 'picking' as picking,
           case when p.promoteur is null or p.promoteur ~ '^[a-z0-9]+_' or p.promoteur like '%(%' then null
                else p.promoteur end as promoteur,
           p.livraison, p.livraison_key, p.fisc, p.gare, p.gare_dist, p.lat, p.lng, p.cp, p.data,
           (select count(*) from lots where lots.programme_id = p.id) as nb,        -- libres + optionnés (décision du 25/11/2026)
           (select count(*) from lots where lots.programme_id = p.id) as nb_tout,
           neuf_slug(p.nom) as s0
      from pige_programmes p
      join v on v.dept = p.dept
       and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
       and (v.cps is null or p.cp = any(v.cps))
     where coalesce(p.source, '') <> 'nomandat'
  ), retenus as (
    select r.*,
           case when r.s0 = '' then 'programme-' || left(r.cle, 6)
                when count(*) over (partition by r.s0) > 1 then r.s0 || '-' || left(r.cle, 4)
                else r.s0 end as slug
      from progs r
     where r.picking or r.nb_tout > 0
  ), fiches as (
    select r.picking, r.livraison_key, r.nb,
           jsonb_build_object(
             'slug', r.slug,
             'pige_id', r.cle,
             'nom', r.nom,
             'promoteur', r.promoteur,
             'quartier', null,
             'livraison', case
                 when r.livraison is null then null
                 when r.livraison = 'En exploitation' or r.livraison_key < a.cle then 'Livré'
                 when r.livraison ~ '^T[1-4] [0-9]{4}$' then
                   (case substr(r.livraison, 2, 1) when '1' then '1er' else substr(r.livraison, 2, 1) || 'e' end)
                   || ' trimestre ' || right(r.livraison, 4)
                 when r.livraison ~ '^S[12] [0-9]{4}$' then
                   (case substr(r.livraison, 2, 1) when '1' then '1er' else '2e' end)
                   || ' semestre ' || right(r.livraison, 4)
                 else r.livraison end,
             'livraison_cle', case when r.livraison_key is null then null
                 else floor(r.livraison_key)::int || '-' || round((r.livraison_key - floor(r.livraison_key)) * 10)::int end,
             'typologies', coalesce((select jsonb_agg(t order by t) from (select distinct typo as t from lots where lots.programme_id = r.id) x), '[]'::jsonb),
             'nb_lots_libres', case when r.picking then null else r.nb end,
             'prix_a_partir_de', null,
             'dispositifs', coalesce((
                 select jsonb_agg(d order by d) from (
                   select distinct case f when 'PTZ' then 'PTZ' when 'TVA réduite' then 'TVA 5,5 %' when 'Accession maîtrisée / BRS' then 'BRS' end as d
                     from jsonb_array_elements_text(case when jsonb_typeof(r.fisc) = 'array' then r.fisc else '[]'::jsonb end) f
                 ) x where d is not null), '[]'::jsonb),
             'gare', case
                 when r.gare ~ '^METRO \S+ .+' then regexp_replace(r.gare, '^METRO (\S+) (.+)$', '\2 (M\1)')
                 when r.gare ~ '^TRAM \S+ .+'  then regexp_replace(r.gare, '^TRAM (\S+) (.+)$', '\2 (T\1)')
                 when r.gare ~ '^RER \S+ .+'   then regexp_replace(r.gare, '^RER (\S+) (.+)$', '\2 (RER \1)')
                 when r.gare ~ '^TRAIN \S+ .+' then regexp_replace(r.gare, '^TRAIN (\S+) (.+)$', '\2 (ligne \1)')
                 else r.gare end,
             'gare_minutes_a_pied', case when r.gare_dist is null then null else greatest(1, ceil(r.gare_dist / 80.0)::int) end,
             'picking', r.picking,
             'image', null,
             'position', case when r.lat is null or r.lng is null then null
                 else jsonb_build_object('latitude', round(r.lat::numeric, 3), 'longitude', round(r.lng::numeric, 3),
                                         -- placé au centre de la ville ou de la rue : la page le dit « Emplacement approximatif »
                                         'approx', coalesce(r.data->>'geo_approx', '') = 'true') end,
             'logements', coalesce((
                 select jsonb_agg(jsonb_build_object('id', l.id, 'typo', l.typo, 'pieces', l.pieces, 'surface', l.surf,
                                                     'etage', l.etage, 'exterieur', l.exterieur, 'statut', l.statut)
                                  -- « v3d » n'apparaît que sur un lot visitable : rien ne change ailleurs
                                  || case when l.v3d then jsonb_build_object('v3d', true) else '{}'::jsonb end
                                  order by l.typo, l.surf, l.id)
                   from lots l where l.programme_id = r.id), '[]'::jsonb)
           )
           -- « visite_3d » n'apparaît que sur un programme qui a sa visite (immeuble) : rien ne change ailleurs
           || case when exists (select 1 from neuf_visites_3d x where x.programme_id = r.id and x.lot_id is null and x.actif)
                   then jsonb_build_object('visite_3d', true) else '{}'::jsonb end as fiche,
           r.promoteur, r.fisc, r.data, r.cp
      from retenus r cross join actuel a
  )
  select jsonb_build_object(
    'version', 1,
    'slug', v.slug,
    'ville', v.ville,
    'cp', (select f.cp from fiches f where f.cp is not null group by f.cp order by count(*) desc, f.cp limit 1),
    'insee', v.insee,
    'dept', v.dept,
    'dept_nom', (select max(f.data->>'dept_nom') from fiches f),
    'maj', (select max(pige_date) from pige_maj),
    'chiffres', jsonb_build_object(
      'nb_programmes', (select count(*) from fiches f where not f.picking),
      'nb_lots_libres', (select count(*) from lots),
      'nb_promoteurs', (select count(distinct f.promoteur) from fiches f where not f.picking),
      'prix_m2_moyen', null,
      'prix_entree', null,
      'livraisons', coalesce((
          select jsonb_object_agg(an, n) from (
            select floor(f.livraison_key)::int::text as an, count(*) as n
              from fiches f cross join actuel a
             where not f.picking and f.livraison_key >= a.cle
             group by 1) x), '{}'::jsonb),
      'typologies', (select jsonb_build_object(
          'T1', count(*) filter (where typo = 'T1'), 'T2', count(*) filter (where typo = 'T2'),
          'T3', count(*) filter (where typo = 'T3'), 'T4', count(*) filter (where typo = 'T4'),
          'T5+', count(*) filter (where typo = 'T5+')) from lots)
    ),
    'guide', jsonb_build_object(
      'intro', null,
      'transports', '[]'::jsonb,
      'zone_ptz', (select case when lower(replace(z, ' ', '')) = 'abis' then 'A bis' else upper(z) end
                     from (select f.data->>'zone' as z from fiches f where f.data->>'zone' is not null) x
                    group by 1 order by count(*) desc limit 1),
      'tva_reduite', coalesce((select bool_or(f.fisc @> '["TVA réduite"]'::jsonb) from fiches f where not f.picking), false)
    ),
    'programmes', coalesce((select jsonb_agg(f.fiche order by f.picking, f.livraison_key nulls last, f.nb desc) from fiches f), '[]'::jsonb)
  )
  from v;
$$;

revoke all on function public.neuf_ville_public(text) from public, anon, authenticated;
grant execute on function public.neuf_ville_public(text) to service_role;

-- 7. Esprit Valmy (Colombes) : à lancer APRÈS le dépôt des 16 fichiers dans l'espace plans3d. -----
--    « fichier » est le chemin dans l'espace (sans « plans3d/ » devant).
-- insert into public.neuf_visites_3d (programme_id, lot_id, fichier)
-- select 'marignan:130', null, '8db4aeab0032/immeuble.html'
-- union all
-- select l.programme_id, l.id, '8db4aeab0032/' || neuf_cle(l.id) || '.html'
--   from public.pige_lots l
--  where l.programme_id = 'marignan:130'
--    and l.n in ('A001','A102','A201','A203','A204','A302','A303','A304','A401','A403','A501','A503','A602','A701','A703')
-- on conflict do nothing;
