-- Tâches hebdomadaires des gérants (demande d'Alex du 16/11/2026).
-- La liste des tâches est écrite dans le CRM (index.html, hb*) ; cette table
-- ne garde que les cases cochées, pour qu'elles soient les mêmes sur le Mac
-- et l'iPhone. Une ligne = une tâche d'une semaine (semaine = le lundi) ou
-- d'un mois (semaine = le 1er du mois, clé « m-… »).
--
-- Droits : gérants seulement (lecture, cocher / décocher). Pas de suppression.

create table public.gerant_hebdo (
  semaine date not null,
  cle text not null check (length(cle) between 1 and 80),
  fait boolean not null default true,
  maj_le timestamptz not null default now(),
  maj_par text,
  primary key (semaine, cle)
);

create or replace function public.gerant_hebdo_avant()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  new.maj_le := now();
  new.maj_par := coalesce(public.mon_prenom(), 'Claude');
  return new;
end $$;
create trigger gerant_hebdo_avant before insert or update on public.gerant_hebdo
  for each row execute function public.gerant_hebdo_avant();
revoke all on function public.gerant_hebdo_avant() from public, anon;

alter table public.gerant_hebdo enable row level security;
create policy gerant_hebdo_lecture on public.gerant_hebdo for select to authenticated using (public.est_gerant());
create policy gerant_hebdo_ajout on public.gerant_hebdo for insert to authenticated with check (public.est_gerant());
create policy gerant_hebdo_maj on public.gerant_hebdo for update to authenticated using (public.est_gerant()) with check (public.est_gerant());

grant select, insert, update on public.gerant_hebdo to authenticated;
grant all on public.gerant_hebdo to service_role;
