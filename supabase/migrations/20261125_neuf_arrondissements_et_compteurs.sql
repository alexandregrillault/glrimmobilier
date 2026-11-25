-- Pages ville : Paris par arrondissement, Pierrefitte rattachée à Saint-Denis, optionnés comptés.
--
-- PRÉPARÉE le 25/11/2026, NON APPLIQUÉE. À appliquer AVANT les fichiers des départements
-- (20261125_neuf_villes_93.sql se sert de la colonne pige_villes créée ici).
--
-- Décisions d'Alex du 25/11/2026, dites à la session CRM :
--   - « Paris, une page par arrondissement » ;
--   - « pierrefite fais comme tu le sens » : Pierrefitte-sur-Seine a fusionné avec Saint-Denis le
--     01/01/2025, son programme est rangé sur la page de Saint-Denis (fait dans le fichier du 93) ;
--   - « Compte aussi les optionnés », après « optionné et libre = libre » (dit à la mère) : sur les
--     pages un optionné s'affiche comme un libre, donc les compteurs les comptent aussi.
--
-- Ce qui change :
--   1. neuf_villes gagne deux colonnes facultatives :
--        pige_villes : les noms de ville de la pige rangés sur cette page (vide = le nom de la ville) ;
--        cps         : ne garder que ces codes postaux (vide = tous). Sert aux arrondissements.
--   2. neuf_prix_public et neuf_ville_public rattachent un programme à sa page par ces colonnes.
--      Pour toutes les villes existantes (colonnes vides) le résultat est le même qu'avant.
--   3. Compteurs de neuf_ville_public : « nb_lots_libres » (programme et ville) et les typologies
--      comptent désormais libres + optionnés. Les noms des champs ne changent pas ; le champ
--      « statut » de chaque logement reste (le site ne l'affiche plus).
--   4. Les 14 arrondissements de Paris qui ont, à la pige du 25/11/2026, au moins un programme à
--      montrer entrent à l'état « prete » : 37 programmes d'extranet et 11 « picking ».
--      Code INSEE de l'arrondissement (75103, 75104…). Le 16e réunit 75016 et 75116.
--      Adresse des pages : /neuf/paris-3e/, /neuf/paris-13e/…
-- Rien n'est mis en ligne : aucune ville ne change d'état.

insert into public.fonctions_backup_20261125 (nom, definition, sauvegarde_le)
select p.proname, pg_get_functiondef(p.oid), now()
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('neuf_prix_public', 'neuf_ville_public');

alter table public.neuf_villes add column if not exists pige_villes text[];
alter table public.neuf_villes add column if not exists cps text[];
comment on column public.neuf_villes.pige_villes is 'Noms de ville de la pige rangés sur cette page ; vide = le nom de la ville.';
comment on column public.neuf_villes.cps is 'Codes postaux gardés (arrondissements de Paris) ; vide = tous.';

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
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
       and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
       and (v.cps is null or p.cp = any(v.cps))
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
       and l.st in ('libre', 'option')
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
                when l.ext then 'Extérieur' end as exterieur
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

-- Mêmes droits qu'avant (create or replace les garde ; répétés pour mémoire).
revoke all on function public.neuf_prix_public(text, text) from public, anon, authenticated;
grant execute on function public.neuf_prix_public(text, text) to service_role;
revoke all on function public.neuf_ville_public(text) from public, anon, authenticated;
grant execute on function public.neuf_ville_public(text) to service_role;

-- Paris par arrondissement.
insert into public.neuf_villes (ville, insee, dept, etat, slug, pige_villes, cps)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville), x.pige_villes, x.cps
  from (values
  ('Paris 3e', '75103', '75', 'prete', array['Paris'], array['75003']),
  ('Paris 4e', '75104', '75', 'prete', array['Paris'], array['75004']),
  ('Paris 7e', '75107', '75', 'prete', array['Paris'], array['75007']),
  ('Paris 8e', '75108', '75', 'prete', array['Paris'], array['75008']),
  ('Paris 9e', '75109', '75', 'prete', array['Paris'], array['75009']),
  ('Paris 12e', '75112', '75', 'prete', array['Paris'], array['75012']),
  ('Paris 13e', '75113', '75', 'prete', array['Paris'], array['75013']),
  ('Paris 14e', '75114', '75', 'prete', array['Paris'], array['75014']),
  ('Paris 15e', '75115', '75', 'prete', array['Paris'], array['75015']),
  ('Paris 16e', '75116', '75', 'prete', array['Paris'], array['75016', '75116']),
  ('Paris 17e', '75117', '75', 'prete', array['Paris'], array['75017']),
  ('Paris 18e', '75118', '75', 'prete', array['Paris'], array['75018']),
  ('Paris 19e', '75119', '75', 'prete', array['Paris'], array['75019']),
  ('Paris 20e', '75120', '75', 'prete', array['Paris'], array['75020'])
  ) as x (ville, insee, dept, etat, pige_villes, cps)
on conflict (ville) do nothing;
