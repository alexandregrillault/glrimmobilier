-- Les deux prix de chaque annonce SeLoger (décision d'Alex du 20/11/2026 : « Le vrai prix et celui haut »).
-- Une annonce est toujours à l'un de ses deux prix : le prix haut (le vrai prix, celui du promoteur)
-- ou le prix bas (prix haut − 3 000 €). La session « SeLoger — Annonces en ligne » alterne entre les deux
-- et a besoin de retenir le vrai prix de chaque annonce : sans cette table, il se perd dès qu'une annonce
-- est au prix bas ou recréée sous un nouveau numéro.
-- Remplie et lue par SQL (outil Supabase de Claude) ; la page My SeLoger Pro ne parle jamais à la base.
-- Aucun écran dans le CRM pour l'instant ; lecture réservée aux gérants, comme seloger_recreation_passages.

create table if not exists public.seloger_prix (
  -- numéro de l'annonce dans My SeLoger Pro
  id_annonce  bigint primary key,
  -- le vrai prix (promoteur), en euros
  prix_haut   integer not null check (prix_haut > 3000),
  -- toujours prix haut − 3 000 € : calculé par la base, on ne peut pas l'écrire à la main
  prix_bas    integer generated always as (prix_haut - 3000) stored,
  -- dernier prix posé et relu sur SeLoger
  etat        text not null check (etat in ('haut', 'bas')),
  -- intitulé de l'annonce (« Théo T3 - ANTONY - 62 M² »), pour relire à l'œil
  reference   text,
  -- numéro de l'ancienne annonce quand celle-ci vient d'une recréation (le prix haut suit l'appartement)
  remplace    bigint,
  -- vide tant que l'annonce est en ligne
  retiree_le  timestamptz,
  -- dernière écriture sur la ligne, tenue par la base
  maj_le      timestamptz not null default now()
);

-- maj_le suit chaque modification, même si l'écriture l'oublie
create or replace function public.seloger_prix_maj()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  new.maj_le := now();
  return new;
end
$$;

drop trigger if exists seloger_prix_maj on public.seloger_prix;
create trigger seloger_prix_maj before update on public.seloger_prix
  for each row execute function public.seloger_prix_maj();

alter table public.seloger_prix enable row level security;
drop policy if exists seloger_prix_gerant on public.seloger_prix;
create policy seloger_prix_gerant on public.seloger_prix
  for select to authenticated using (public.est_gerant());

-- Dans cette base, toute nouvelle table reçoit d'office tous les droits pour anon et authenticated :
-- on les retire d'abord, puis on ne rend que la lecture aux utilisateurs connectés (filtrée par la policy).
revoke all on public.seloger_prix from anon, authenticated;
grant select on public.seloger_prix to authenticated;
grant all on public.seloger_prix to service_role;

revoke all on function public.seloger_prix_maj() from public, anon, authenticated;
