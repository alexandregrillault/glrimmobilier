-- Carte des programmes : la base prépare la carte une fois par mise à jour de la pige
-- au lieu de la reconstruire (12 Mo, ~20 000 lots) à chaque ouverture (05/11/2026).
-- Avant : 0,8 à 7 s par ouverture, coupure à 8 s (erreur 500 « Impossible de charger la carte »).
-- Après : 0,08 s côté base. Appliquée le 05/11/2026.

-- 1. Sauvegarde de la fonction actuelle
create table if not exists public.fonctions_backup_20261105 (proname text, definition text, sauve_le timestamptz default now());
alter table public.fonctions_backup_20261105 enable row level security;
revoke all on public.fonctions_backup_20261105 from anon, authenticated;
grant all on public.fonctions_backup_20261105 to service_role;
insert into public.fonctions_backup_20261105 (proname, definition)
select p.proname, pg_get_functiondef(p.oid) from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname = 'pige_carte';

-- 2. Construction complète (l'ancien corps de pige_carte), réservée à la base
create or replace function public.pige_carte_construire()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'meta', (select json_build_object('pige_date', pige_date, 'prev_date', prev_date, 'nb_dedoublonnes', nb_dedoublonnes,
                                      'nouveaux_programmes', nb_nouveaux_programmes, 'nouveaux_lots', nb_nouveaux_lots, 'baisses', nb_baisses,
                                      'nb_programmes', nb_programmes, 'nb_lots', nb_lots, 'nb_logements', nb_logements, 'nb_libres', nb_libres)
             from pige_maj order by id desc limit 1),
    'genere', (select to_char(max(maj_at), 'YYYY-MM-DD') from pige_programmes),
    'programmes', coalesce((select json_agg(jsonb_strip_nulls(data || jsonb_build_object('premiere_pige', premiere_pige))) from pige_programmes), '[]'::json),
    'lots', coalesce((select json_agg(jsonb_strip_nulls(data)) from pige_lots), '[]'::json)
  );
$$;
revoke all on function public.pige_carte_construire() from public, anon, authenticated;
grant execute on function public.pige_carte_construire() to service_role;

-- 3. La copie prête (une seule ligne)
create table if not exists public.pige_carte_cache (
  id int primary key default 1 check (id = 1),
  signature text not null,      -- état de la pige au moment de la construction
  version text not null,        -- étiquette lue par le navigateur pour savoir si sa mémoire est à jour
  data json not null,
  construit_at timestamptz not null default now()
);
alter table public.pige_carte_cache enable row level security;  -- aucune règle : lecture uniquement via pige_carte()
revoke all on public.pige_carte_cache from anon;
grant select on public.pige_carte_cache to authenticated;
grant all on public.pige_carte_cache to service_role;

-- Signature : change dès qu'un programme ou un lot est ajouté, modifié ou retiré, ou qu'une pige est enregistrée
create or replace function public.pige_carte_signature()
returns text language sql stable security definer set search_path = public as $$
  select concat_ws('|',
    (select max(id) from pige_maj),
    (select count(*) || '/' || coalesce(max(maj_at)::text, '') from pige_programmes),
    (select count(*) || '/' || coalesce(max(maj_at)::text, '') from pige_lots));
$$;
revoke all on function public.pige_carte_signature() from public, anon, authenticated;
grant execute on function public.pige_carte_signature() to service_role;

-- Met la copie à jour si la pige a bougé (appelée toutes les 5 minutes, ou à la main avec forcer => true)
create or replace function public.pige_carte_maj(forcer boolean default false)
returns text language plpgsql volatile security definer set search_path = public as $$
declare s text := pige_carte_signature();
begin
  if not forcer and exists (select 1 from pige_carte_cache where id = 1 and signature = s) then
    return 'à jour';
  end if;
  insert into pige_carte_cache (id, signature, version, data, construit_at)
  values (1, s, to_char(now(), 'YYYYMMDDHH24MISS') || '-' || left(md5(s), 8), pige_carte_construire(), now())
  on conflict (id) do update set signature = excluded.signature, version = excluded.version,
                                 data = excluded.data, construit_at = excluded.construit_at;
  return 'reconstruite';
end $$;
revoke all on function public.pige_carte_maj(boolean) from public, anon, authenticated;
grant execute on function public.pige_carte_maj(boolean) to service_role;

-- 4. Ce que lit la carte : la copie prête (construction en direct seulement si elle n'existe pas encore)
create or replace function public.pige_carte()
returns json language sql stable security definer set search_path = public as $$
  select coalesce((select data from pige_carte_cache where id = 1), pige_carte_construire());
$$;
revoke all on function public.pige_carte() from public, anon;
grant execute on function public.pige_carte() to authenticated, service_role;

-- Étiquette de la copie : quelques octets, pour que le navigateur sache s'il peut réutiliser sa mémoire
create or replace function public.pige_carte_version()
returns text language sql stable security definer set search_path = public as $$
  select version from pige_carte_cache where id = 1;
$$;
revoke all on function public.pige_carte_version() from public, anon;
grant execute on function public.pige_carte_version() to authenticated, service_role;

-- 5. Première construction + vérification toutes les 5 minutes
select public.pige_carte_maj(true);
select cron.schedule('pige_carte_copie', '*/5 * * * *', 'select public.pige_carte_maj()');
