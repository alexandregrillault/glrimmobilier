-- Tickets des vendeurs vers les gérants (demande d'Alex du 11/11/2026).
-- Un vendeur écrit ou dicte un ticket depuis « Mes tickets » ; les gérants le
-- voient dans « Tickets », le prennent en charge et y répondent.
--
-- Droits :
--   - lecture : un gérant voit tout, un vendeur seulement ses tickets ;
--   - création : toute personne connectée ; l'auteur est TOUJOURS celui qui est
--     connecté (trigger), jamais ce qu'envoie la page ;
--   - modification (statut, réponse) : gérants seulement ;
--   - « réponse lue » : l'auteur, par la RPC ticket_reponse_vue ;
--   - aucune suppression.

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  cree_le timestamptz not null default now(),
  auteur text not null,
  type text not null check (type in ('probleme', 'question', 'demande', 'client', 'autre')),
  urgence text not null default 'normal' check (urgence in ('normal', 'jour', 'bloquant')),
  titre text not null check (length(titre) between 1 and 140),
  message text not null check (length(message) between 1 and 4000),
  saisie text not null default 'ecrit' check (saisie in ('ecrit', 'vocal')),
  contact_id uuid references public.contacts(id) on delete set null,
  contact_nom text check (contact_nom is null or length(contact_nom) <= 140),
  contexte jsonb not null default '{}'::jsonb,
  statut text not null default 'nouveau' check (statut in ('nouveau', 'en_cours', 'regle')),
  pris_par text,
  reponse text check (reponse is null or length(reponse) <= 4000),
  repondu_par text,
  repondu_le timestamptz,
  reponse_vue_le timestamptz
);
create index tickets_auteur_idx on public.tickets (auteur, cree_le desc);
create index tickets_statut_idx on public.tickets (statut, cree_le desc);

-- Création : l'auteur et l'état de départ sont fixés par la base
create or replace function public.tickets_avant_creation()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  new.auteur := public.mon_prenom();
  if new.auteur is null then raise exception 'Profil inconnu'; end if;
  new.cree_le := now();
  new.statut := 'nouveau';
  new.pris_par := null; new.reponse := null; new.repondu_par := null;
  new.repondu_le := null; new.reponse_vue_le := null;
  return new;
end $$;
create trigger tickets_avant_creation before insert on public.tickets
  for each row execute function public.tickets_avant_creation();

-- Modification par un gérant : ce que le vendeur a écrit ne bouge pas ;
-- qui a pris en charge / répondu est noté par la base.
create or replace function public.tickets_avant_maj()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(current_setting('glr.ticket_vue', true), '') = '1' then return new; end if;
  new.id := old.id; new.cree_le := old.cree_le; new.auteur := old.auteur;
  new.type := old.type; new.urgence := old.urgence; new.titre := old.titre;
  new.message := old.message; new.saisie := old.saisie; new.contact_id := old.contact_id;
  new.contact_nom := old.contact_nom; new.contexte := old.contexte;
  if new.statut = 'en_cours' and old.statut is distinct from 'en_cours' then
    new.pris_par := public.mon_prenom();
  end if;
  if new.reponse is distinct from old.reponse then
    new.repondu_par := public.mon_prenom();
    new.repondu_le := now();
    new.reponse_vue_le := null;
  else
    new.repondu_par := old.repondu_par; new.repondu_le := old.repondu_le;
    new.reponse_vue_le := old.reponse_vue_le;
  end if;
  return new;
end $$;
create trigger tickets_avant_maj before update on public.tickets
  for each row execute function public.tickets_avant_maj();

alter table public.tickets enable row level security;
create policy tickets_lecture on public.tickets for select to authenticated
  using (public.est_gerant() or auteur = public.mon_prenom());
create policy tickets_creation on public.tickets for insert to authenticated
  with check (public.mon_prenom() is not null);
create policy tickets_maj on public.tickets for update to authenticated
  using (public.est_gerant()) with check (public.est_gerant());

grant select, insert, update on public.tickets to authenticated;
grant all on public.tickets to service_role;

-- Le vendeur a lu la réponse : enlève la pastille de « Mes tickets »
create or replace function public.ticket_reponse_vue(p_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  perform set_config('glr.ticket_vue', '1', true);
  update public.tickets set reponse_vue_le = now()
   where id = p_id and auteur = public.mon_prenom() and reponse is not null and reponse_vue_le is null;
  perform set_config('glr.ticket_vue', '', true);
end $$;
revoke all on function public.ticket_reponse_vue(uuid) from public, anon;
grant execute on function public.ticket_reponse_vue(uuid) to authenticated, service_role;
revoke all on function public.tickets_avant_creation() from public, anon;
revoke all on function public.tickets_avant_maj() from public, anon;
