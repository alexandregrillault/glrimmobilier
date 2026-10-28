-- Robot de recréation des annonces SeLoger (glr-pige/outils/seloger_recreer.py), 28/10/2026.
-- Un passage par jour sur le Mac d'Alex ; son bilan groupé est envoyé ici pour la rubrique
-- « Robot SeLoger » de la page Annonces (gérants seulement, demande d'Alex du 28/10/2026).

create table if not exists public.seloger_recreation_passages (
  id          bigserial primary key,
  jour        date not null,
  debut       timestamptz,
  fin         timestamptz,
  prevu       integer,
  recrees     integer not null default 0,
  supprimees  integer not null default 0,
  en_ligne    integer,
  arret       text,
  resume      text[] not null default '{}',
  -- détail annonce par annonce (ancienne → nouvelle, intitulés, prix, photos), pour retrouver un cas précis
  detail      jsonb not null default '[]'::jsonb,
  recu_le     timestamptz not null default now()
);
create index if not exists seloger_recreation_passages_jour on public.seloger_recreation_passages (jour desc);

alter table public.seloger_recreation_passages enable row level security;
drop policy if exists seloger_recreation_passages_gerant on public.seloger_recreation_passages;
create policy seloger_recreation_passages_gerant on public.seloger_recreation_passages
  for select to authenticated using (public.est_gerant());

grant select on public.seloger_recreation_passages to authenticated;
grant all on public.seloger_recreation_passages to service_role;
grant usage, select on sequence public.seloger_recreation_passages_id_seq to service_role;

-- Écriture par le robot, avec la même clé que le robot de pige (app_secrets « robot_pige »,
-- trousseau du Mac, service glr-pige) : pas d'accès direct à la table.
create or replace function public.robot_seloger_bilan(p_cle text, p_bilan jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id bigint;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  insert into public.seloger_recreation_passages (jour, debut, fin, prevu, recrees, supprimees, en_ligne, arret, resume, detail)
  values (
    (p_bilan->>'date')::date,
    nullif(p_bilan->>'debut', '')::timestamptz,
    nullif(p_bilan->>'fin', '')::timestamptz,
    nullif(p_bilan->>'prevu', '')::integer,
    coalesce((p_bilan->>'recrees')::integer, 0),
    coalesce((p_bilan->>'supprimees')::integer, 0),
    nullif(p_bilan->>'en_ligne', '')::integer,
    nullif(p_bilan->>'arret', ''),
    coalesce(array(select jsonb_array_elements_text(p_bilan->'resume')), '{}'),
    coalesce(p_bilan->'faites', '[]'::jsonb)
  )
  returning id into v_id;
  return v_id;
end
$$;

revoke all on function public.robot_seloger_bilan(text, jsonb) from public;
grant execute on function public.robot_seloger_bilan(text, jsonb) to anon, authenticated, service_role;
