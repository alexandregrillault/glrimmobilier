-- Todo des gérants (demande d'Alex du 12/11/2026).
-- Chaque ligne est une étape d'un sujet. Cocher une étape la fait disparaître
-- de la liste ; elle reste dans l'historique avec qui l'a cochée et quand.
-- Claude y ajoute aussi des étapes (« rajoute dans la todo ») par SQL :
-- dans ce cas cree_par vaut 'Claude'.
--
-- Droits : gérants seulement (lecture, ajout, cocher / décocher). Pas de suppression.

create table public.gerant_todo (
  id uuid primary key default gen_random_uuid(),
  sujet text not null check (length(sujet) between 1 and 140),
  etape text not null check (length(etape) between 1 and 500),
  ordre int not null default 0,
  cree_le timestamptz not null default now(),
  cree_par text,
  fait_le timestamptz,
  fait_par text
);
create index gerant_todo_ouvert_idx on public.gerant_todo (fait_le, sujet, ordre);

create or replace function public.gerant_todo_avant()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if tg_op = 'INSERT' then
    new.cree_le := coalesce(new.cree_le, now());
    new.cree_par := coalesce(public.mon_prenom(), new.cree_par, 'Claude');
    new.fait_le := null; new.fait_par := null;
  else
    -- seul l'état « fait » change depuis le CRM ; qui et quand sont notés par la base
    new.id := old.id; new.cree_le := old.cree_le; new.cree_par := old.cree_par;
    if new.fait_le is not null and old.fait_le is null then
      new.fait_le := now(); new.fait_par := coalesce(public.mon_prenom(), 'Claude');
    elsif new.fait_le is null then
      new.fait_par := null;
    else
      new.fait_le := old.fait_le; new.fait_par := old.fait_par;
    end if;
  end if;
  return new;
end $$;
create trigger gerant_todo_avant before insert or update on public.gerant_todo
  for each row execute function public.gerant_todo_avant();
revoke all on function public.gerant_todo_avant() from public, anon;

alter table public.gerant_todo enable row level security;
create policy gerant_todo_lecture on public.gerant_todo for select to authenticated using (public.est_gerant());
create policy gerant_todo_ajout on public.gerant_todo for insert to authenticated with check (public.est_gerant());
create policy gerant_todo_maj on public.gerant_todo for update to authenticated using (public.est_gerant()) with check (public.est_gerant());

grant select, insert, update on public.gerant_todo to authenticated;
grant all on public.gerant_todo to service_role;
