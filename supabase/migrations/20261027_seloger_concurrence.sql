-- Relevé SeLoger de la concurrence, pour la page Annonces du CRM (27/10/2026).
-- Une ligne par annonce relevée : pour chaque ville où la pige a du stock réel et chaque typologie (T1…T5),
-- les 10 annonces neuves les moins chères en tri prix croissant, nos annonces (GLR IMMOBILIER) jusqu'à la 120e place,
-- et le total d'annonces de la typologie. Une ligne sans rang = aucune annonce pour la typologie.
-- Produit par pige/current/scripts/seloger_concurrence.js, importé depuis le CRM (Annonces → « Importer un relevé SeLoger »).
-- Gérants seulement, en lecture comme en écriture.
create table if not exists public.seloger_concurrence (
  id bigint generated always as identity primary key,
  releve date not null,
  cle text not null,          -- ville, même clé que annonces_stock() (« PARIS 15 » pour les arrondissements)
  typo text not null,         -- T1…T5 (T5 = 5 pièces et plus)
  total int not null,         -- annonces neuves de la typologie dans la ville
  rang int,                   -- place en tri prix croissant
  prix numeric,
  surface numeric,
  annonceur text,
  promoteur boolean,          -- annonce publiée par un promoteur (sinon cabinet / agence)
  glr boolean not null default false,
  cree date,                  -- date de création de l'annonce sur SeLoger
  sid text,                   -- identifiant SeLoger de l'annonce
  importe_le timestamptz not null default now()
);
create index if not exists seloger_concurrence_releve on public.seloger_concurrence (releve, cle, typo);

alter table public.seloger_concurrence enable row level security;
create policy seloger_concurrence_gerant on public.seloger_concurrence
  for all to authenticated using (est_gerant()) with check (est_gerant());

grant select, insert, delete on public.seloger_concurrence to authenticated;
grant all on public.seloger_concurrence to service_role;
