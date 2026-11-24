-- Pages ville du site (www.glrimmobilier.com/neuf/<ville>/) : prix des logements servis par la base.
--
-- PAS ENCORE APPLIQUÉE (préparée le 24/11/2026, en attente de l'accord d'Alex).
--
-- Décision d'Alex du 24/11/2026 : les prix sont visibles sans compte (« si tu peux mettre les prix,
-- juste pas le plans »), mais ils ne sont écrits ni dans les pages ni dans le dépôt public du site :
-- la page programme les demande à l'edge function neuf-prix, qui appelle neuf_prix_public().
--
-- Ce que crée cette migration :
--   1. neuf_cle(text)        : clé publique d'un programme ou d'un lot (12 caractères), pour ne jamais
--                              publier l'identifiant de la pige (« accueil:lathenee-1/a001 » dit par
--                              quel intranet nous passons et le numéro du lot).
--   2. neuf_villes           : les villes publiées (une seule liste pour le fabricant et pour les prix).
--   3. neuf_prix_appels      : compteur des demandes, pour limiter l'aspiration en masse.
--   4. neuf_prix_public()    : la lecture elle-même, réservée à service_role.
--
-- Rien n'est ouvert à anon. Aucune donnée existante n'est modifiée.

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

-- 2. Villes publiées ------------------------------------------------------------------------
create table if not exists public.neuf_villes (
  ville    text primary key,            -- écrite comme dans pige_programmes.ville
  publie   boolean not null default true,
  cree_le  timestamptz not null default now()
);

alter table public.neuf_villes enable row level security;
revoke all on public.neuf_villes from public, anon;
grant select on public.neuf_villes to authenticated;
grant all on public.neuf_villes to service_role;

drop policy if exists neuf_villes_lecture on public.neuf_villes;
create policy neuf_villes_lecture on public.neuf_villes
  for select to authenticated using (true);

insert into public.neuf_villes (ville) values
  ('Aubervilliers'), ('Colombes'), ('Drancy'), ('L''Haÿ-les-Roses'), ('Villiers-sur-Marne')
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
-- Rend { statut: 'ok', maj, prix: { <clé du lot>: prix }, tva_reduite: [ <clés> ] }
--   ou { statut: 'inconnu' }  (clé fausse, programme picking ou sans mandat, ville non publiée :
--                              même réponse, pour ne rien apprendre à celui qui tâtonne)
--   ou { statut: 'limite' }   (trop de demandes).
--
-- Prix servi : le prix TVA 20 % quand la grille le donne ; sinon le prix TVA 5,5 %, et la clé du
-- lot est alors dans « tva_reduite » pour que la page le dise (prix sous conditions de ressources).
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
    join neuf_villes v on v.ville = p.ville and v.publie
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
           round(coalesce(p20, p55, p)) as prix,
           (p20 is null and (p55 is not null or tva in ('5.5', '5,5'))) as reduite
      from brut
  )
  select coalesce(jsonb_object_agg(cle, prix), '{}'::jsonb),
         coalesce(jsonb_agg(cle) filter (where reduite), '[]'::jsonb)
    into v_prix, v_reduite
    from choisi
   where prix between 50000 and 3000000;

  return jsonb_build_object(
    'statut', 'ok',
    'maj', (select max(pige_date) from pige_maj),
    'prix', v_prix,
    'tva_reduite', v_reduite
  );
end;
$$;

revoke all on function public.neuf_prix_public(text, text) from public, anon, authenticated;
grant execute on function public.neuf_prix_public(text, text) to service_role;
