-- Plans 3D, suite : le plan du promoteur de chaque logement, après le formulaire, sur tous les programmes montrés.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE.
-- Décisions d'Alex du 27/11/2026 (session mère) : « mets le plan du promoteur après le formulaire », puis
-- « ok pour le B » : les plans sont convertis en images par le robot de pige et rangés dans un espace privé.
-- Exception voulue à la règle des noms de promoteurs (le cartouche du plan porte le nom), limitée à
-- l'après-formulaire.
--
--   0. Sauvegarde de neuf_ville_public et neuf_3d_programme (versions en place) dans fonctions_backup_20261127.
--   1. Espace PRIVÉ « plans2d » : <clé lot>/<page>.webp (1.webp, 2.webp…), 5 Mo par fichier, images seulement.
--   2. neuf_plans_2d : une ligne par lot converti, remplie par le robot de pige (contrat plus bas).
--      neuf_plans_2d_a_faire : la liste de travail du robot (lots montrés dont le plan manque ou a changé).
--   3. neuf_ville_public : « p2d »: true sur chaque lot converti (vrai seulement).
--   4. neuf_3d_programme : ne répond plus que pour un programme montré (ville publiée, ni picking ni sans
--      mandat). La fonction plans-3d refuse alors l'inscription (404) pour une autre clé.
--   5. neuf_2d_vues + neuf_2d_plan(...) : chemin de l'image d'une page pour un jeton valide, mêmes compteurs
--      que la 3D (40 par jeton, 60 par adresse, par jour), note « Plan 2D : lot … » à la première ouverture.
--   6. neuf_3d_formulaire(p_ip) : limite du formulaire en base, 3 envois par tranche de 10 minutes.
-- Rien n'est retiré ni effacé.

insert into public.fonctions_backup_20261127 (nom, definition)
select 'neuf_ville_public(text) avec v3d', pg_get_functiondef('public.neuf_ville_public(text)'::regprocedure)
on conflict (nom) do nothing;
insert into public.fonctions_backup_20261127 (nom, definition)
select 'neuf_3d_programme(text)', pg_get_functiondef('public.neuf_3d_programme(text)'::regprocedure)
on conflict (nom) do nothing;

-- 1. Espace privé des plans en image -----------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('plans2d', 'plans2d', false, 5242880, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- 2. Plans convertis (rempli par le robot de pige) ---------------------------------------------
-- CONTRAT DU ROBOT (session Pige et robots) :
--   - Liste de travail : select * from public.neuf_plans_2d_a_faire  (lot_id, cle, plan_url, plan_maj).
--     Ce sont les lots montrés sur le site qui ont un plan dans documents_lot et dont l'image manque, ou
--     dont le plan a changé (plan_url différent, ou documents_lot.maj_le plus récent que la conversion).
--   - Pour chaque lot : télécharger plan_url ; PDF → chaque page (8 au plus) rendue en image ; JPG/PNG →
--     la seule page. Image WebP, 1 600 px sur le grand côté, qualité 80 (viser moins de 600 Ko, 5 Mo maximum).
--   - Dépôt (clé de service) dans l'espace plans2d, en remplaçant l'existant : <cle>/1.webp, <cle>/2.webp…
--   - Puis : insert into public.neuf_plans_2d (lot_id, pages, source_url, source_maj, converti_le)
--            values (…, now()) on conflict (lot_id) do update set pages = excluded.pages, source_url = …,
--            source_maj = excluded.source_maj, converti_le = now();
--     source_url = documents_lot.plan_url lu, source_maj = documents_lot.maj_le lu (la colonne plan_maj de la vue).
--   - Un plan illisible : ne rien écrire pour ce lot (il reste dans la liste, le robot le retentera).
--   - Jamais de suppression dans l'espace ni dans la table.
create table if not exists public.neuf_plans_2d (
  lot_id      text primary key,            -- pige_lots.id (jamais montré : le site ne voit que neuf_cle)
  pages       integer not null check (pages between 1 and 8),
  source_url  text not null,               -- documents_lot.plan_url converti
  source_maj  timestamptz,                 -- documents_lot.maj_le au moment de la conversion
  converti_le timestamptz not null default now()
);
alter table public.neuf_plans_2d enable row level security;
revoke all on public.neuf_plans_2d from public, anon;
grant select on public.neuf_plans_2d to authenticated;
grant all on public.neuf_plans_2d to service_role;

create or replace view public.neuf_plans_2d_a_faire
with (security_invoker = true) as
  select l.id as lot_id, neuf_cle(l.id) as cle, d.plan_url, d.maj_le as plan_maj
    from pige_lots l
    join pige_programmes p on p.id = l.programme_id
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
    join documents_lot d on d.lot_id = l.id and d.plan_url is not null
    left join neuf_plans_2d z on z.lot_id = l.id
   where coalesce(p.source, '') not in ('picking', 'nomandat')
     and l.st in ('libre', 'option')
     and l.type in ('Appartement', 'Maison')
     and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
     and (z.lot_id is null or z.source_url is distinct from d.plan_url
          or (d.maj_le is not null and (z.source_maj is null or d.maj_le > z.source_maj)));
revoke all on public.neuf_plans_2d_a_faire from public, anon, authenticated;
grant select on public.neuf_plans_2d_a_faire to service_role;

-- 3. neuf_ville_public : version en place (avec v3d) + p2d ----------------------------------------
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
           exists (select 1 from neuf_visites_3d x where x.lot_id = l.id and x.actif) as v3d,
           -- Plan du promoteur (27/11/2026) : converti en image par le robot, visible après le formulaire
           exists (select 1 from neuf_plans_2d z where z.lot_id = l.id and z.pages > 0) as p2d
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
                                  || case when l.p2d then jsonb_build_object('p2d', true) else '{}'::jsonb end
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

-- 4. neuf_3d_programme : programmes montrés seulement ---------------------------------------------
create or replace function public.neuf_3d_programme(p_cle text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('nom', p.nom, 'ville', p.ville)
    from pige_programmes p
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
   where neuf_cle(p.id) = p_cle
     and coalesce(p.source, '') not in ('picking', 'nomandat')
   limit 1;
$$;
revoke all on function public.neuf_3d_programme(text) from public, anon, authenticated;
grant execute on function public.neuf_3d_programme(text) to service_role;

-- 5a. Premier passage sur un plan ---------------------------------------------------------------
create table if not exists public.neuf_2d_vues (
  empreinte text not null,
  lot_id    text not null,
  vu_le     timestamptz not null default now(),
  primary key (empreinte, lot_id)
);
alter table public.neuf_2d_vues enable row level security;
revoke all on public.neuf_2d_vues from public, anon, authenticated;
grant all on public.neuf_2d_vues to service_role;

-- 5b. L'image d'une page du plan d'un lot, pour un jeton valide ---------------------------------
-- Réponse : { statut: 'ok', chemin: '<cle>/<page>.webp', pages } (chemin dans l'espace plans2d)
--         | { statut: 'jeton' } | { statut: 'inconnu' } | { statut: 'limite' }.
create or replace function public.neuf_2d_plan(p_programme text, p_lot text, p_page integer, p_empreinte text, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_par_jeton constant integer := 40;
  c_par_ip    constant integer := 60;
  v_jour    date := (now() at time zone 'Europe/Paris')::date;
  v_contact uuid;
  v_nj      integer;
  v_ni      integer;
  v_lot     text;
  v_pages   integer;
  v_page    integer := coalesce(p_page, 1);
  v_n       integer;
  v_ligne   text;
begin
  select contact_id into v_contact
    from neuf_3d_jetons where empreinte = p_empreinte and expire_le > now();
  if p_empreinte is null or not found then
    return jsonb_build_object('statut', 'jeton');
  end if;

  insert into neuf_3d_appels (qui, jour, n) values ('j:' || p_empreinte, v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_nj;
  insert into neuf_3d_appels (qui, jour, n) values ('ip:' || coalesce(p_ip, 'inconnue'), v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_ni;
  if v_nj > c_par_jeton or v_ni > c_par_ip then
    return jsonb_build_object('statut', 'limite');
  end if;

  -- Un lot montré sur le site (mêmes filtres que neuf_ville_public), du bon programme, converti.
  select l.id, z.pages into v_lot, v_pages
    from pige_lots l
    join pige_programmes p on p.id = l.programme_id
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
    join neuf_plans_2d z on z.lot_id = l.id and z.pages > 0
   where neuf_cle(p.id) = p_programme
     and neuf_cle(l.id) = p_lot
     and coalesce(p.source, '') not in ('picking', 'nomandat')
     and l.st in ('libre', 'option')
     and l.type in ('Appartement', 'Maison')
     and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
   limit 1;
  if v_lot is null or v_page < 1 or v_page > v_pages then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  -- Première ouverture de ce plan par ce client : une ligne dans les notes de sa fiche.
  if v_contact is not null then
    insert into neuf_2d_vues (empreinte, lot_id) values (p_empreinte, v_lot) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      select '[' || to_char(now() at time zone 'Europe/Paris', 'DD/MM/YYYY') || '] Plan 2D : lot ' || l.n
             || coalesce(' (' || l.typo || coalesce(', ' || replace(rtrim(to_char(l.surf, 'FM999990.9'), '.'), '.', ',') || ' m²', '') || ')', '')
             || coalesce(', ' || p.nom, '') || coalesce(' à ' || p.ville, '')
        into v_ligne
        from pige_lots l join pige_programmes p on p.id = l.programme_id
       where l.id = v_lot;
      if v_ligne is not null then
        update contacts set notes = case when coalesce(notes, '') = '' then v_ligne else notes || E'\n' || v_ligne end
         where id = v_contact;
      end if;
    end if;
  end if;

  return jsonb_build_object('statut', 'ok', 'chemin', p_lot || '/' || v_page || '.webp', 'pages', v_pages);
end;
$$;
revoke all on function public.neuf_2d_plan(text, text, integer, text, text) from public, anon, authenticated;
grant execute on function public.neuf_2d_plan(text, text, integer, text, text) to service_role;

-- 6. Limite du formulaire en base : 3 envois par tranche de 10 minutes et par adresse -------------
create or replace function public.neuf_3d_formulaire(p_ip text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tranche text := to_char(now() at time zone 'Europe/Paris', 'HH24') || ':'
                    || (extract(minute from now())::int / 10)::text;
  v_n integer;
begin
  insert into neuf_3d_appels (qui, jour, n)
  values ('f:' || coalesce(p_ip, 'inconnue') || ':' || v_tranche, (now() at time zone 'Europe/Paris')::date, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_n;
  return v_n <= 3;   -- true = envoi accepté
end;
$$;
revoke all on function public.neuf_3d_formulaire(text) from public, anon, authenticated;
grant execute on function public.neuf_3d_formulaire(text) to service_role;
