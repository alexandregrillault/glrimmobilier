-- Parrainage (décisions d'Alex du 12/11/2026).
--
-- N'importe qui peut parrainer (client ou non). Récompense : carte cadeau de
-- 1 000 € au parrain et de 500 € au filleul, due quand le filleul a signé chez
-- le notaire (vente non supprimée, signature notaire passée, ou facturée / payée).
-- Une récompense par filleul, même s'il achète plusieurs lots.
-- Le filleul suit l'attribution habituelle des leads du site (Théophile).
--
-- parrains            : une ligne par parrain, avec son code de lien personnel
-- contacts.parrain_id : le parrain d'une fiche (filleul)
-- parrainage_cartes   : cartes cadeaux envoyées (une ligne = une carte envoyée)
-- parrainage_suivi()  : pour les gérants, les filleuls et ce qui reste à envoyer

create table public.parrains (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  prenom text not null check (length(prenom) between 1 and 60),
  nom text check (nom is null or length(nom) <= 80),
  email text check (email is null or length(email) <= 160),
  telephone text check (telephone is null or length(telephone) <= 40),
  contact_id uuid references public.contacts(id) on delete set null,
  origine text not null default 'site' check (origine in ('site', 'crm')),
  accord_le timestamptz,
  cree_le timestamptz not null default now(),
  cree_par text
);
create unique index parrains_email_uidx on public.parrains (lower(email)) where email is not null and email <> '';
create unique index parrains_contact_uidx on public.parrains (contact_id) where contact_id is not null;

alter table public.contacts add column if not exists parrain_id uuid references public.parrains(id) on delete set null;
create index if not exists contacts_parrain_idx on public.contacts (parrain_id) where parrain_id is not null;

-- Code de 6 caractères sans lettres ambiguës (pas de O/0, I/1).
create or replace function public.parrain_nouveau_code()
returns text language plpgsql volatile set search_path to 'public' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.parrains where code = c);
  end loop;
  return c;
end $$;

create or replace function public.parrains_avant()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if tg_op = 'INSERT' then
    new.code := coalesce(nullif(new.code, ''), public.parrain_nouveau_code());
    new.cree_le := now();
    new.cree_par := coalesce(public.mon_prenom(), new.cree_par);
    if new.email is not null then new.email := lower(trim(new.email)); end if;
  else
    new.id := old.id; new.code := old.code; new.cree_le := old.cree_le; new.cree_par := old.cree_par;
  end if;
  return new;
end $$;
create trigger parrains_avant before insert or update on public.parrains
  for each row execute function public.parrains_avant();
revoke all on function public.parrains_avant() from public, anon;
revoke all on function public.parrain_nouveau_code() from public, anon;

create table public.parrainage_cartes (
  id uuid primary key default gen_random_uuid(),
  filleul_id uuid not null,
  beneficiaire text not null check (beneficiaire in ('parrain', 'filleul')),
  parrain_id uuid references public.parrains(id) on delete set null,
  montant int not null check (montant > 0),
  note text check (note is null or length(note) <= 500),
  envoyee_le timestamptz not null default now(),
  envoyee_par text,
  unique (filleul_id, beneficiaire)
);

create or replace function public.parrainage_cartes_avant()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if tg_op = 'INSERT' then
    new.envoyee_le := now();
    new.envoyee_par := coalesce(public.mon_prenom(), new.envoyee_par);
  else
    new.id := old.id; new.filleul_id := old.filleul_id; new.beneficiaire := old.beneficiaire;
    new.envoyee_le := old.envoyee_le; new.envoyee_par := old.envoyee_par;
  end if;
  return new;
end $$;
create trigger parrainage_cartes_avant before insert or update on public.parrainage_cartes
  for each row execute function public.parrainage_cartes_avant();
revoke all on function public.parrainage_cartes_avant() from public, anon;

-- Droits
alter table public.parrains enable row level security;
create policy parrains_lecture on public.parrains for select to authenticated using (true);
create policy parrains_ajout on public.parrains for insert to authenticated with check (origine = 'crm');
create policy parrains_maj on public.parrains for update to authenticated using (public.est_gerant()) with check (public.est_gerant());
grant select, insert, update on public.parrains to authenticated;
grant all on public.parrains to service_role;

alter table public.parrainage_cartes enable row level security;
create policy parrainage_cartes_gerants on public.parrainage_cartes for all to authenticated
  using (public.est_gerant()) with check (public.est_gerant());
grant select, insert, update, delete on public.parrainage_cartes to authenticated;
grant all on public.parrainage_cartes to service_role;

-- Suivi pour l'Espace Gérant : un filleul par ligne.
create or replace function public.parrainage_suivi()
returns table (
  filleul_id uuid, filleul_nom text, filleul_statut text, filleul_vendeur text, filleul_recu_le timestamptz,
  parrain_id uuid, parrain_code text, parrain_nom text, parrain_email text, parrain_telephone text,
  vente_programme text, vente_lot text, signe_le date, signe boolean,
  carte_parrain_le timestamptz, carte_filleul_le timestamptz
)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.est_gerant() then raise exception 'Réservé aux gérants'; end if;
  return query
  select c.id, coalesce(nullif(trim(coalesce(c.prenom, '') || ' ' || coalesce(c.nom_famille, '')), ''), c.nom),
         c.statut, c.vendeur, coalesce(c.recu_le, c.created_at),
         p.id, p.code, trim(p.prenom || ' ' || coalesce(p.nom, '')), p.email, p.telephone,
         v.programme, v.lot, v.signe_le, v.id is not null,
         (select k.envoyee_le from public.parrainage_cartes k where k.filleul_id = c.id and k.beneficiaire = 'parrain'),
         (select k.envoyee_le from public.parrainage_cartes k where k.filleul_id = c.id and k.beneficiaire = 'filleul')
  from public.contacts c
  join public.parrains p on p.id = c.parrain_id
  left join lateral (
    select x.id, x.programme, x.lot, coalesce(x."dateSignatureNotaire", x.created_at::date) as signe_le
    from public.ventes x
    where x.contact_id = c.id and x.deleted_at is null
      and (x.statut in ('facture', 'facture-payee') or x."dateSignatureNotaire" <= current_date)
    order by coalesce(x."dateSignatureNotaire", x.created_at::date)
    limit 1
  ) v on true
  order by (v.id is not null) desc, coalesce(c.recu_le, c.created_at) desc;
end $$;
revoke all on function public.parrainage_suivi() from public, anon;
grant execute on function public.parrainage_suivi() to authenticated, service_role;
