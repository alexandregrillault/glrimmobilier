-- Questionnaire du robot Instagram de Quoi de neuf, posé question par question dans les
-- messages privés (demande d'Alex du 03/11/2026). Une ligne par personne : l'étape en cours
-- et les réponses déjà données. Les réponses sont effacées si la personne refuse d'être
-- recontactée, et la ligne disparaît après 365 jours sans échange (edge function qdn-instagram).

create table if not exists public.qdn_instagram_conversations (
  ig_user     text primary key,                 -- id Instagram (IGSID) de la personne
  etape       text not null default 'zone',     -- zone, typologie, budget, prenom, telephone, email, accord, fini, refus, invitation
  reponses    jsonb not null default '{}'::jsonb,
  essais      integer not null default 0,       -- réponses refusées à l'étape en cours (téléphone, e-mail)
  origine     text,                             -- commentaire ou message
  media_id    text,
  contact_id  uuid,
  debut_le    timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

alter table public.qdn_instagram_conversations enable row level security;

drop policy if exists qdn_instagram_conv_lecture_gerants on public.qdn_instagram_conversations;
create policy qdn_instagram_conv_lecture_gerants on public.qdn_instagram_conversations
  for select to authenticated using (public.est_gerant());

grant select on public.qdn_instagram_conversations to authenticated;
grant all on public.qdn_instagram_conversations to service_role;
