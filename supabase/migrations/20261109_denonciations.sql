-- Dénonciation automatique des leads sur les extranets promoteurs (demande d'Alex du 09/11/2026).
-- Le robot (glr-pige/robot/denonciation_*.py, GitHub Actions) lit le nom, l'e-mail et le téléphone
-- d'un lead par robot_contact_denonciation, sans que ces données passent dans les journaux GitHub,
-- et note chaque essai ou dénonciation dans la table denonciations (registre, preuve de la date).
-- Lecture réservée aux gérants pendant la validation compte par compte ; les vendeurs la verront
-- sur la fiche client et dans la composition des sélections quand l'écran sera fait.

create table if not exists public.denonciations (
  id          bigserial primary key,
  contact_id  uuid not null references public.contacts(id) on delete cascade,
  plateforme  text not null,              -- « immolead », puis les autres extranets
  compte      text not null,              -- ex. « care » (comptes_immolead.json)
  promoteur   text,                       -- nom de la fiche promoteur du CRM
  programme   text,
  ville       text,
  -- essai : formulaire rempli sans dénonciation définitive ; enregistree : acceptée par
  -- l'extranet ; deja_connu : le promoteur connaissait déjà le client ; echec ; a_faire_main
  statut      text not null check (statut in ('essai', 'enregistree', 'deja_connu', 'echec', 'a_faire_main')),
  detail      text,                       -- message de l'extranet, étape atteinte
  preuve      text,                       -- capture : passage GitHub et nom du fichier
  fait_le     timestamptz not null default now()
);
create index if not exists denonciations_contact on public.denonciations (contact_id, fait_le desc);

alter table public.denonciations enable row level security;
drop policy if exists denonciations_gerant on public.denonciations;
create policy denonciations_gerant on public.denonciations
  for select to authenticated using (public.est_gerant());

grant select on public.denonciations to authenticated;
grant all on public.denonciations to service_role;
grant usage, select on sequence public.denonciations_id_seq to service_role;

-- Coordonnées d'un lead pour le robot (clé robot_pige, comme robot_identifiants).
create or replace function public.robot_contact_denonciation(p_cle text, p_id uuid)
returns table (id uuid, nom_complet text, email text, telephone text, lieu text)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
    select c.id,
           coalesce(nullif(trim(concat_ws(' ', c.prenom, c.nom_famille)), ''), c.nom),
           c.email, c.telephone, c.lieu
    from public.contacts c
    where c.id = p_id and coalesce(c.statut, '') <> 'Stop';
end
$$;

-- Le robot note le résultat de chaque essai ou dénonciation.
create or replace function public.robot_denonciation_noter(p_cle text, p_ligne jsonb)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail, preuve)
  values ((p_ligne->>'contact_id')::uuid, p_ligne->>'plateforme', p_ligne->>'compte', p_ligne->>'promoteur',
          p_ligne->>'programme', p_ligne->>'ville', p_ligne->>'statut', left(p_ligne->>'detail', 4000), p_ligne->>'preuve')
  returning denonciations.id into v_id;
  return v_id;
end
$$;

revoke all on function public.robot_contact_denonciation(text, uuid) from public;
revoke all on function public.robot_denonciation_noter(text, jsonb) from public;
grant execute on function public.robot_contact_denonciation(text, uuid) to anon, authenticated, service_role;
grant execute on function public.robot_denonciation_noter(text, jsonb) to anon, authenticated, service_role;
