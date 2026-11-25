-- Pages ville du site (www.glrimmobilier.com/neuf/<ville>/) : prix des logements servis par la base.
--
-- APPLIQUÉE le 25/11/2026 (accord d'Alex : « pages villes je suis d'accord et deploie »), collée par
-- Alex dans l'éditeur SQL de Supabase : l'outil de Claude refuse ce fichier (drop policy, delete).
--
-- Décision d'Alex du 24/11/2026 : les prix sont visibles sans compte (« si tu peux mettre les prix,
-- juste pas le plans »), mais ils ne sont écrits ni dans les pages ni dans le dépôt public du site :
-- la page programme les demande à l'edge function neuf-prix, qui appelle neuf_prix_public().
--
-- Ce que crée cette migration :
--   1. neuf_cle(text)        : clé publique d'un programme ou d'un lot (12 caractères), pour ne jamais
--                              publier l'identifiant de la pige (« accueil:lathenee-1/a001 » dit par
--                              quel intranet nous passons et le numéro du lot).
--      neuf_slug(text)       : nom d'adresse (« le-plessis-robinson »).
--   2. neuf_villes           : les villes des pages, avec leur code INSEE et leur état
--                              (« prete » = fabricable, « publiee » = en ligne, prix servis).
--   3. neuf_prix_appels      : compteur des demandes, pour limiter l'aspiration en masse.
--   4. neuf_prix_public()    : la lecture des prix, réservée à service_role.
--   5. neuf_ville_public()   : le JSON d'une ville pour le fabricant du site (aucun prix),
--                              réservée à service_role.
--   6. neuf_villes_publiees() et neuf_ville_publiee() : la même lecture pour le générateur du
--                              site, avec la clé publique, villes « publiee » seulement.
--
-- Ouvert à anon : seulement les deux lectures du point 6. Aucune donnée existante n'est modifiée.

-- 1. Clé publique ---------------------------------------------------------------------------
create or replace function public.neuf_cle(p_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select substr(md5('glr-neuf:' || p_id), 1, 12);
$$;

revoke all on function public.neuf_cle(text) from public, anon;
grant execute on function public.neuf_cle(text) to authenticated, service_role;

create or replace function public.neuf_slug(p_texte text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '-' from regexp_replace(
    translate(replace(replace(lower(coalesce(p_texte, '')), 'œ', 'oe'), 'æ', 'ae'),
              'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ', 'aaaaaaceeeeiiiinooooouuuuyy'),
    '[^a-z0-9]+', '-', 'g'));
$$;

revoke all on function public.neuf_slug(text) from public, anon;
grant execute on function public.neuf_slug(text) to authenticated, service_role;

-- 2. Villes des pages ------------------------------------------------------------------------
-- etat = 'prete'   : le fabricant peut lire ses données, rien n'est en ligne, aucun prix servi ;
-- etat = 'publiee' : page en ligne, neuf-prix sert ses prix. Passer une ville en « publiee » se fait
--                    sur un « pousse » d'Alex : update public.neuf_villes set etat = 'publiee' where ville = '…';
create table if not exists public.neuf_villes (
  ville    text primary key,            -- écrite comme dans pige_programmes.ville
  insee    text not null unique,        -- code commune (contour, lieux, espaces verts)
  dept     text not null,
  slug     text not null unique,        -- /neuf/<slug>/
  etat     text not null default 'prete' check (etat in ('prete', 'publiee')),
  cree_le  timestamptz not null default now()
);

alter table public.neuf_villes enable row level security;
revoke all on public.neuf_villes from public, anon;
grant select on public.neuf_villes to authenticated;
grant all on public.neuf_villes to service_role;

drop policy if exists neuf_villes_lecture on public.neuf_villes;
create policy neuf_villes_lecture on public.neuf_villes
  for select to authenticated using (true);

-- Décisions d'Alex du 24/11/2026 : l'essai commence par Colombes (seule publiée), puis s'étend à
-- tout le 92 (« fais moi ça pour toutes les villes du 92 »). Les 34 communes du 92 qui ont, à la
-- pige du 24/11/2026, au moins un programme à montrer (33 avec des logements libres, plus Châtillon
-- qui n'a qu'un programme « picking »). Absentes : Vaucresson (rien à montrer) et
-- Marnes-la-Coquette (aucun programme en base).
insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Antony', '92002', '92', 'prete'),
  ('Asnières-sur-Seine', '92004', '92', 'prete'),
  ('Bagneux', '92007', '92', 'prete'),
  ('Bois-Colombes', '92009', '92', 'prete'),
  ('Boulogne-Billancourt', '92012', '92', 'prete'),
  ('Bourg-la-Reine', '92014', '92', 'prete'),
  ('Châtenay-Malabry', '92019', '92', 'prete'),
  ('Châtillon', '92020', '92', 'prete'),
  ('Chaville', '92022', '92', 'prete'),
  ('Clamart', '92023', '92', 'prete'),
  ('Clichy', '92024', '92', 'prete'),
  ('Colombes', '92025', '92', 'publiee'),
  ('Courbevoie', '92026', '92', 'prete'),
  ('Fontenay-aux-Roses', '92032', '92', 'prete'),
  ('Garches', '92033', '92', 'prete'),
  ('La Garenne-Colombes', '92035', '92', 'prete'),
  ('Gennevilliers', '92036', '92', 'prete'),
  ('Issy-les-Moulineaux', '92040', '92', 'prete'),
  ('Levallois-Perret', '92044', '92', 'prete'),
  ('Malakoff', '92046', '92', 'prete'),
  ('Meudon', '92048', '92', 'prete'),
  ('Montrouge', '92049', '92', 'prete'),
  ('Nanterre', '92050', '92', 'prete'),
  ('Neuilly-sur-Seine', '92051', '92', 'prete'),
  ('Le Plessis-Robinson', '92060', '92', 'prete'),
  ('Puteaux', '92062', '92', 'prete'),
  ('Rueil-Malmaison', '92063', '92', 'prete'),
  ('Saint-Cloud', '92064', '92', 'prete'),
  ('Sceaux', '92071', '92', 'prete'),
  ('Sèvres', '92072', '92', 'prete'),
  ('Suresnes', '92073', '92', 'prete'),
  ('Vanves', '92075', '92', 'prete'),
  ('Ville-d''Avray', '92077', '92', 'prete'),
  ('Villeneuve-la-Garenne', '92078', '92', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;

-- 3. Compteur des demandes ------------------------------------------------------------------
-- ip = empreinte de l'adresse (calculée par l'edge function), jamais l'adresse elle-même.
-- Table technique : service_role seulement, aucune règle de lecture (ni commercial ni client).
create table if not exists public.neuf_prix_appels (
  ip         text not null,
  heure      timestamptz not null,      -- début de l'heure
  programme  text not null,             -- clé publique demandée
  n          integer not null default 1,
  primary key (ip, heure, programme)
);

create index if not exists neuf_prix_appels_heure on public.neuf_prix_appels (heure);

alter table public.neuf_prix_appels enable row level security;
revoke all on public.neuf_prix_appels from public, anon, authenticated;
grant all on public.neuf_prix_appels to service_role;

-- 4. Lecture des prix d'un programme --------------------------------------------------------
-- Rend { statut: 'ok', maj, prix: { <clé du lot>: prix TVA 20 % }, prix_tva_reduite: { <clé du lot>: prix TVA 5,5 % } }
--   ou { statut: 'inconnu' }  (clé fausse, programme picking ou sans mandat, ville non publiée (ou seulement « prete ») :
--                              même réponse, pour ne rien apprendre à celui qui tâtonne)
--   ou { statut: 'limite' }   (trop de demandes).
--
-- Décision d'Alex du 24/11/2026 (« Les deux prix ») : la page montre le prix TVA 20 % et le prix
-- TVA 5,5 % quand la grille donne les deux. Un lot peut n'être que dans l'une des deux listes, ou
-- dans aucune (pas de prix : « sur demande »). La colonne pige_lots.prix mélange les deux taux :
-- elle ne sert que de repli, rangée d'après data.tva.
-- Seulement les lots libres de type Appartement ou Maison, prix entre 50 000 et 3 000 000 €.
create or replace function public.neuf_prix_public(p_cle text, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_heure   timestamptz := date_trunc('hour', now());
  v_ip      text := left(coalesce(nullif(p_ip, ''), 'inconnue'), 64);
  v_prog    text;
  v_nb_prog integer;
  v_nb_jour integer;
  v_total   integer;
  v_prix    jsonb;
  v_reduite jsonb;
begin
  if p_cle is null or p_cle !~ '^[0-9a-f]{12}$' then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  -- Compter la demande, qu'elle aboutisse ou non.
  insert into neuf_prix_appels (ip, heure, programme) values (v_ip, v_heure, p_cle)
  on conflict (ip, heure, programme) do update set n = neuf_prix_appels.n + 1;

  -- Ménage : de temps en temps, retirer les compteurs de plus de deux jours.
  if random() < 0.02 then
    delete from neuf_prix_appels where heure < now() - interval '2 days';
  end if;

  select count(distinct programme) into v_nb_prog
    from neuf_prix_appels where ip = v_ip and heure > now() - interval '1 hour';
  select coalesce(sum(n), 0) into v_nb_jour
    from neuf_prix_appels where ip = v_ip and heure > now() - interval '1 day';
  select coalesce(sum(n), 0) into v_total
    from neuf_prix_appels where heure > now() - interval '1 day';

  -- 30 programmes différents par heure et 200 demandes par jour pour une même adresse ;
  -- 20 000 demandes par jour toutes adresses confondues (garde-fou si l'aspirateur change d'adresse).
  if v_nb_prog > 30 or v_nb_jour > 200 or v_total > 20000 then
    return jsonb_build_object('statut', 'limite');
  end if;

  select p.id into v_prog
    from pige_programmes p
    join neuf_villes v on v.ville = p.ville and v.dept = p.dept and v.etat = 'publiee'
   where neuf_cle(p.id) = p_cle
     and coalesce(p.source, '') not in ('picking', 'nomandat')
   limit 1;

  if v_prog is null then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  with brut as (
    select l.id,
           case when l.data->>'prix20' ~ '^[0-9]+(\.[0-9]+)?$' then nullif((l.data->>'prix20')::numeric, 0) end as p20,
           case when l.data->>'prix55' ~ '^[0-9]+(\.[0-9]+)?$' then nullif((l.data->>'prix55')::numeric, 0) end as p55,
           nullif(l.prix, 0) as p,
           l.data->>'tva' as tva
      from pige_lots l
     where l.programme_id = v_prog
       and l.st = 'libre'
       and l.type in ('Appartement', 'Maison')
  ), choisi as (
    select neuf_cle(id) as cle,
           round(case when p20 is not null then p20
                      when p55 is null and coalesce(tva, '') not in ('5.5', '5,5') then p end) as prix_20,
           round(case when p55 is not null then p55
                      when p20 is null and tva in ('5.5', '5,5') then p end) as prix_55
      from brut
  )
  select coalesce(jsonb_object_agg(cle, prix_20) filter (where prix_20 between 50000 and 3000000), '{}'::jsonb),
         coalesce(jsonb_object_agg(cle, prix_55) filter (where prix_55 between 50000 and 3000000), '{}'::jsonb)
    into v_prix, v_reduite
    from choisi;

  return jsonb_build_object(
    'statut', 'ok',
    'maj', (select max(pige_date) from pige_maj),
    'prix', v_prix,
    'prix_tva_reduite', v_reduite
  );
end;
$$;

revoke all on function public.neuf_prix_public(text, text) from public, anon, authenticated;
grant execute on function public.neuf_prix_public(text, text) to service_role;

-- 5. Le JSON d'une ville pour le fabricant du site --------------------------------------------
-- Rend exactement le format v1 des pages ville (note « Pages ville - format des données », section
-- « FAIT FOI ») pour une ville de neuf_villes, donnée par son nom ou son slug ; null sinon.
--
-- Jamais dans ce JSON : un prix (les trois champs de prix du format sont rendus vides tant qu'Alex
-- n'a pas tranché), un plan, une image (elles viennent des intranets), un identifiant de la pige,
-- un numéro de lot, une commission, un programme « sans mandat ».
-- Programmes rendus : ceux d'un extranet qui ont au moins un logement libre (Appartement ou Maison,
-- typologie connue), et les « picking » (sans logements : « grille sur demande »).
-- Promoteur : vide quand la base n'a qu'un nom technique (« immolead_care ») ou une remarque
-- interne entre parenthèses (« WEMO (agrégateur…) », « catella (réseau) »).
-- Dispositifs : seulement PTZ, TVA 5,5 % et BRS (jamais LLI ni LMNP).
-- Étage inconnu : « etage » vide (la page écrit « étage non précisé »). Position approchée : « approx » vrai.
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
           l.typo, l.pieces, l.surf,
           case when l.etage ~ '^-?[0-9]+$' then l.etage::int end as etage,
           case when lower(coalesce(l.data->>'annexes', '')) like '%jardin%'   then 'Jardin'
                when lower(coalesce(l.data->>'annexes', '')) like '%terrasse%' then 'Terrasse'
                when lower(coalesce(l.data->>'annexes', '')) like '%loggia%'   then 'Loggia'
                when lower(coalesce(l.data->>'annexes', '')) like '%balcon%'   then 'Balcon'
                when l.ext then 'Extérieur' end as exterieur
      from pige_lots l
      join pige_programmes p on p.id = l.programme_id
      join v on v.ville = p.ville and v.dept = p.dept
     where coalesce(p.source, '') not in ('picking', 'nomandat')
       and l.st = 'libre'
       and l.type in ('Appartement', 'Maison')
       and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
  ), progs as (
    select p.id, neuf_cle(p.id) as cle, p.nom,
           coalesce(p.source, '') = 'picking' as picking,
           case when p.promoteur is null or p.promoteur ~ '^[a-z0-9]+_' or p.promoteur like '%(%' then null
                else p.promoteur end as promoteur,
           p.livraison, p.livraison_key, p.fisc, p.gare, p.gare_dist, p.lat, p.lng, p.cp, p.data,
           (select count(*) from lots where lots.programme_id = p.id) as nb,
           neuf_slug(p.nom) as s0
      from pige_programmes p
      join v on v.ville = p.ville and v.dept = p.dept
     where coalesce(p.source, '') <> 'nomandat'
  ), retenus as (
    select r.*,
           case when r.s0 = '' then 'programme-' || left(r.cle, 6)
                when count(*) over (partition by r.s0) > 1 then r.s0 || '-' || left(r.cle, 4)
                else r.s0 end as slug
      from progs r
     where r.picking or r.nb > 0
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
                                                     'etage', l.etage, 'exterieur', l.exterieur)
                                  order by l.typo, l.surf, l.id)
                   from lots l where l.programme_id = r.id), '[]'::jsonb)
           ) as fiche,
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

-- ---------------------------------------------------------------------------------------------
-- 6. Lecture par le générateur du site (ajout du 25/11/2026)
-- ---------------------------------------------------------------------------------------------
-- Décision d'Alex du 25/11/2026 : mise en ligne automatique des pages ville, avec garde-fous.
-- Le générateur tourne dans glr-site, dépôt public : il n'a pas la clé de service. Il lit donc
-- avec la clé publique du site, mais SEULEMENT les villes à l'état « publiee », c'est-à-dire ce
-- qui est de toute façon écrit ensuite dans les pages et dans le dépôt public du site.
-- Une ville « prete » reste invisible ici (même réponse vide qu'une ville inconnue) ;
-- neuf_ville_public(), qui rend aussi les villes « prete », reste réservée à service_role.
-- Aucun prix dans ces deux lectures : la limite d'appels de neuf_prix_public() ne change pas.

-- La liste des villes à fabriquer.
create or replace function public.neuf_villes_publiees()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('ville', ville, 'slug', slug, 'insee', insee, 'dept', dept)
                            order by dept, slug), '[]'::jsonb)
    from neuf_villes
   where etat = 'publiee';
$$;

revoke all on function public.neuf_villes_publiees() from public;
grant execute on function public.neuf_villes_publiees() to anon, authenticated, service_role;

-- Le JSON d'une ville publiée (nom ou slug) ; null pour une ville « prete » ou inconnue.
create or replace function public.neuf_ville_publiee(p_ville text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select neuf_ville_public(v.ville)
    from neuf_villes v
   where (v.ville = p_ville or v.slug = p_ville)
     and v.etat = 'publiee'
   limit 1;
$$;

revoke all on function public.neuf_ville_publiee(text) from public;
grant execute on function public.neuf_ville_publiee(text) to anon, authenticated, service_role;
