-- Plan de masse du promoteur, après le formulaire, sur la fiche programme (comme les plans des logements).
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE.
-- Demande d'Alex du 27/11/2026 (session mère) : « pour le plan de masse mets aussi la possibilité d'avoir
-- celui du promoteur, l'image qu'il donne, comme pour les plans soit on a la vision 3D soit la photo du
-- promoteur ». Visible après le formulaire (le plan porte le nom du promoteur) : à confirmer par Alex.
--
--   0. Sauvegarde de neuf_ville_public (version en place) dans fonctions_backup_20261127.
--   1. neuf_masses_2d + neuf_masses_2d_erreurs : plans de masse convertis (ou illisibles), remplis par le robot.
--      Images dans l'espace privé plans2d, sous masse/<clé programme>/<page>.webp.
--   2. neuf_masses_2d_a_faire : liste de travail (programmes montrés dont le plan de masse manque ou a changé).
--   3. robot_masses_2d_a_faire (anon, clé du robot), robot_masses_2d_verifier / robot_masses_2d_enregistrer
--      (service_role, pour plans2d-depot v2).
--   4. neuf_2d_masse(...) : chemin de l'image pour un jeton valide, compteurs communs (40 par jeton, 60 par
--      adresse, par jour), note « Plan de masse : … » une fois par jeton et par programme.
--   5. neuf_ville_public : « pm »: true sur un programme dont le plan de masse est converti (vrai seulement).
-- Rien n'est retiré ni effacé.

insert into public.fonctions_backup_20261127 (nom, definition)
select 'neuf_ville_public(text) avec p2d', pg_get_functiondef('public.neuf_ville_public(text)'::regprocedure)
on conflict (nom) do nothing;

-- 1. Plans de masse convertis ---------------------------------------------------------------------
create table if not exists public.neuf_masses_2d (
  programme_id text primary key,           -- pige_programmes.id (le site ne voit que neuf_cle)
  pages        integer not null check (pages between 1 and 8),
  source_url   text not null,              -- documents_programme.plan_masse_url converti
  source_maj   timestamptz,
  converti_le  timestamptz not null default now()
);
alter table public.neuf_masses_2d enable row level security;
revoke all on public.neuf_masses_2d from public, anon;
grant select on public.neuf_masses_2d to authenticated;
grant all on public.neuf_masses_2d to service_role;

create table if not exists public.neuf_masses_2d_erreurs (
  programme_id text primary key,
  source_url   text not null,
  erreur       text not null,
  le           timestamptz not null default now()
);
alter table public.neuf_masses_2d_erreurs enable row level security;
revoke all on public.neuf_masses_2d_erreurs from public, anon;
grant select on public.neuf_masses_2d_erreurs to authenticated;
grant all on public.neuf_masses_2d_erreurs to service_role;

-- 2. Liste de travail ---------------------------------------------------------------------------
create or replace view public.neuf_masses_2d_a_faire
with (security_invoker = true) as
  select p.id as programme_id, neuf_cle(p.id) as cle, d.plan_masse_url as plan_url, d.maj_le as plan_maj
    from pige_programmes p
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
    join documents_programme d on d.programme_id = p.id and d.plan_masse_url is not null
    left join neuf_masses_2d z on z.programme_id = p.id
    left join neuf_masses_2d_erreurs e on e.programme_id = p.id and e.source_url = d.plan_masse_url
   where coalesce(p.source, '') not in ('picking', 'nomandat')
     and exists (select 1 from pige_lots l where l.programme_id = p.id and l.st in ('libre', 'option')
                  and l.type in ('Appartement', 'Maison') and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+'))
     and e.programme_id is null
     and (z.programme_id is null or z.source_url is distinct from d.plan_masse_url
          or (d.maj_le is not null and (z.source_maj is null or d.maj_le > z.source_maj)));
revoke all on public.neuf_masses_2d_a_faire from public, anon, authenticated;
grant select on public.neuf_masses_2d_a_faire to service_role;

-- 3. Portes du robot ----------------------------------------------------------------------------
create or replace function public.robot_masses_2d_a_faire(p_cle text, p_limite integer default 1000, p_apres text default null)
returns table (programme_id text, cle text, plan_url text, plan_maj timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
    select a.programme_id, a.cle, a.plan_url, a.plan_maj
      from public.neuf_masses_2d_a_faire a
     where p_apres is null or a.programme_id > p_apres
     order by a.programme_id
     limit least(greatest(coalesce(p_limite, 1000), 1), 5000);
end;
$$;
revoke all on function public.robot_masses_2d_a_faire(text, integer, text) from public;
grant execute on function public.robot_masses_2d_a_faire(text, integer, text) to anon, authenticated, service_role;

create or replace function public.robot_masses_2d_verifier(p_cle text, p_programme_id text, p_cle_prog text, p_source_url text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_cle is null or length(p_cle) < 32
         or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then 'acces_refuse'
    when p_programme_id is null or neuf_cle(p_programme_id) is distinct from p_cle_prog
         or not exists (select 1 from public.documents_programme d where d.programme_id = p_programme_id and d.plan_masse_url = p_source_url) then 'inconnu'
    else 'ok' end;
$$;
revoke all on function public.robot_masses_2d_verifier(text, text, text, text) from public, anon, authenticated;
grant execute on function public.robot_masses_2d_verifier(text, text, text, text) to service_role;

create or replace function public.robot_masses_2d_enregistrer(
  p_cle text, p_programme_id text, p_cle_prog text, p_pages integer, p_source_url text, p_source_maj timestamptz, p_erreur text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.robot_masses_2d_verifier(p_cle, p_programme_id, p_cle_prog, p_source_url) = 'acces_refuse' then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if public.robot_masses_2d_verifier(p_cle, p_programme_id, p_cle_prog, p_source_url) <> 'ok' then
    return 'inconnu';
  end if;
  if coalesce(p_pages, 0) between 1 and 8 then
    insert into neuf_masses_2d (programme_id, pages, source_url, source_maj, converti_le)
    values (p_programme_id, p_pages, p_source_url, p_source_maj, now())
    on conflict (programme_id) do update set pages = excluded.pages, source_url = excluded.source_url,
      source_maj = excluded.source_maj, converti_le = now();
    return 'ok';
  end if;
  if coalesce(p_pages, 0) = 0 and nullif(btrim(coalesce(p_erreur, '')), '') is not null then
    insert into neuf_masses_2d_erreurs (programme_id, source_url, erreur, le)
    values (p_programme_id, p_source_url, left(p_erreur, 500), now())
    on conflict (programme_id) do update set source_url = excluded.source_url, erreur = excluded.erreur, le = now();
    return 'ok';
  end if;
  return 'inconnu';
end;
$$;
revoke all on function public.robot_masses_2d_enregistrer(text, text, text, integer, text, timestamptz, text) from public, anon, authenticated;
grant execute on function public.robot_masses_2d_enregistrer(text, text, text, integer, text, timestamptz, text) to service_role;

-- 4. Le plan de masse d'un programme, pour un jeton valide -----------------------------------------
-- Réponse : { statut: 'ok', chemin: 'masse/<cle>/<page>.webp', pages } | 'jeton' | 'inconnu' | 'limite'.
create or replace function public.neuf_2d_masse(p_programme text, p_page integer, p_empreinte text, p_ip text)
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
  v_prog    text;
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

  select p.id, m.pages into v_prog, v_pages
    from pige_programmes p
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
    join neuf_masses_2d m on m.programme_id = p.id and m.pages > 0
   where neuf_cle(p.id) = p_programme
     and coalesce(p.source, '') not in ('picking', 'nomandat')
   limit 1;
  if v_prog is null or v_page < 1 or v_page > v_pages then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  -- Première ouverture de ce plan de masse par ce client : une ligne dans les notes de sa fiche.
  if v_contact is not null then
    insert into neuf_2d_vues (empreinte, lot_id) values (p_empreinte, 'masse:' || v_prog) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      select '[' || to_char(now() at time zone 'Europe/Paris', 'DD/MM/YYYY') || '] Plan de masse : '
             || coalesce(p.nom, 'programme') || coalesce(' à ' || p.ville, '')
        into v_ligne from pige_programmes p where p.id = v_prog;
      update contacts set notes = case when coalesce(notes, '') = '' then v_ligne else notes || E'\n' || v_ligne end
       where id = v_contact;
    end if;
  end if;

  return jsonb_build_object('statut', 'ok', 'chemin', 'masse/' || p_programme || '/' || v_page || '.webp', 'pages', v_pages);
end;
$$;
revoke all on function public.neuf_2d_masse(text, integer, text, text) from public, anon, authenticated;
grant execute on function public.neuf_2d_masse(text, integer, text, text) to service_role;

-- 5. neuf_ville_public : version en place (v3d, p2d) + pm ----------------------------------------
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
                   then jsonb_build_object('visite_3d', true) else '{}'::jsonb end
           -- « pm » : plan de masse du promoteur converti en image (27/11/2026), vrai seulement
           || case when exists (select 1 from neuf_masses_2d m where m.programme_id = r.id and m.pages > 0)
                   then jsonb_build_object('pm', true) else '{}'::jsonb end as fiche,
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
