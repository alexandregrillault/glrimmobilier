-- Vidéos « Quoi de neuf » de la semaine, choisies depuis l'onglet Marché du CRM (27/10/2026).
-- Rythme d'Alex : lundi l'épisode récap des programmes « Vidéo du lundi », puis un focus par jour
-- (mardi, mercredi, jeudi) dans l'ordre de passage ; « Bonus » = vidéo en plus, postée le vendredi
-- de la semaine en cours.
-- semaine = le lundi de la semaine de diffusion (lundi qui vient pour « lundi », lundi en cours pour « bonus »).
-- Lu aussi par le rappel du matin et par le skill qdn-propositions. Gérants seulement.
create table if not exists public.qdn_videos (
  id uuid primary key default gen_random_uuid(),
  programme_id text not null,
  nom text,
  ville text,
  promoteur text,
  type text not null check (type in ('lundi', 'bonus')),
  semaine date not null,
  ordre int not null default 1,
  statut text not null default 'a_faire' check (statut in ('a_faire', 'faite', 'postee')),
  cree_par uuid default auth.uid(),
  cree_le timestamptz not null default now(),
  unique (programme_id, type, semaine)
);
create index if not exists qdn_videos_semaine on public.qdn_videos (semaine, type, ordre);

alter table public.qdn_videos enable row level security;
create policy qdn_videos_gerant on public.qdn_videos
  for all to authenticated using (est_gerant()) with check (est_gerant());

grant select, insert, update, delete on public.qdn_videos to authenticated;
grant all on public.qdn_videos to service_role;
-- Les droits par défaut du projet donnent tout à anon et trop à authenticated : on resserre.
revoke all on public.qdn_videos from anon;
revoke truncate, references, trigger on public.qdn_videos from authenticated;
