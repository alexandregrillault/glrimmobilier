-- Robot Instagram de Quoi de neuf (demande d'Alex du 03/11/2026) :
-- journal des commentaires « PLANS » et des messages privés traités par l'edge function
-- qdn-instagram, pour ne jamais répondre deux fois au même événement ni relancer
-- quelqu'un plus d'une fois par semaine.
-- Les clés (jeton Instagram, secret de l'application Meta) vont dans app_secrets,
-- jamais dans ce dépôt public.

create table if not exists public.qdn_instagram_evenements (
  id          text primary key,            -- id du commentaire ou du message Instagram
  type        text not null check (type in ('commentaire', 'message')),
  ig_user     text,                        -- id Instagram (IGSID) de la personne
  ig_pseudo   text,
  texte       text,
  media_id    text,
  recu_le     timestamptz not null default now(),
  repondu     boolean not null default false,
  resultat    jsonb
);

create index if not exists qdn_instagram_evenements_user on public.qdn_instagram_evenements (ig_user, recu_le desc);

alter table public.qdn_instagram_evenements enable row level security;

-- Lecture réservée aux gérants (suivi du robot) ; écriture par l'edge function seulement.
drop policy if exists qdn_instagram_lecture_gerants on public.qdn_instagram_evenements;
create policy qdn_instagram_lecture_gerants on public.qdn_instagram_evenements
  for select to authenticated using (public.est_gerant());

grant select on public.qdn_instagram_evenements to authenticated;
grant all on public.qdn_instagram_evenements to service_role;
