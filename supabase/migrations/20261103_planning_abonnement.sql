-- Abonnement au planning depuis le téléphone (demande d'Alex du 03/11/2026)
--
-- Chaque vendeur a un lien secret, personnel, que l'app Calendrier de son
-- téléphone relit toute seule (edge function `planning-ics`). Le lien ne porte
-- aucune session : la clé EST l'autorisation, d'où 48 caractères aléatoires.
-- La table n'est lisible par personne côté navigateur : la clé ne sort que par
-- la RPC ci-dessous, et seulement pour le vendeur connecté. « Renouveler »
-- remplace la clé : l'ancien lien cesse de marcher (téléphone perdu, départ).

create table if not exists public.planning_abonnements (
  vendeur   text primary key,                 -- prénom, comme creneaux.vendeur
  cle       text not null unique,
  cree_le   timestamptz not null default now()
);

alter table public.planning_abonnements enable row level security;
-- Aucune policy : ni lecture ni écriture directe depuis le CRM.

grant select, insert, update, delete on public.planning_abonnements to authenticated, service_role;

create or replace function public.planning_abonnement_cle(renouveler boolean default false)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v text := public.mon_prenom();
  k text;
begin
  if v is null then raise exception 'profil_inconnu'; end if;
  if not renouveler then
    select cle into k from public.planning_abonnements where vendeur = v;
    if k is not null then return k; end if;
  end if;
  k := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.planning_abonnements (vendeur, cle) values (v, k)
    on conflict (vendeur) do update set cle = excluded.cle, cree_le = now();
  return k;
end $$;

revoke all on function public.planning_abonnement_cle(boolean) from public, anon;
grant execute on function public.planning_abonnement_cle(boolean) to authenticated, service_role;
