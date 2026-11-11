-- « Pas de réponse » sans changer le statut (décision d'Alex du 11/11/2026) :
-- un client en Suivi, Sélections, Retour documentation ou Finaliser la vente
-- qui ne décroche pas garde son statut ; on note seulement la tentative
-- (date + commercial) dans contacts.appels, comme le fait le passage en
-- « Sans réponse » (trigger contacts_journal_appel).
-- Un client « Nouveau » continue de passer en « Sans réponse » (relance jusqu'au 3e essai).
--
-- Droits de l'appelant (security invoker) : la policy contacts_maj et le trigger
-- contacts_touch_action s'appliquent. appels n'entre pas dans les champs qui
-- comptent comme action : la paternité et derniere_action_le ne bougent pas.

create or replace function public.contact_appel_sans_reponse(p_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $$
declare
  v_statut text;
  v_appels jsonb;
begin
  select statut into v_statut from public.contacts where id = p_id;
  if not found then
    raise exception 'Client introuvable';
  end if;
  if v_statut is null or v_statut not in ('Suivi', 'Sélections', 'Retour documentation', 'Finaliser la vente') then
    raise exception 'Statut « % » : utiliser le passage en Sans réponse', coalesce(v_statut, '—');
  end if;

  update public.contacts
     set appels = coalesce(appels, '[]'::jsonb) || jsonb_build_array(
           jsonb_build_object('le', now(), 'vendeur', coalesce(public.mon_prenom(), vendeur)))
   where id = p_id
  returning appels into v_appels;

  if not found then
    raise exception 'Modification refusée sur ce client';
  end if;
  return v_appels;
end;
$$;

revoke all on function public.contact_appel_sans_reponse(uuid) from public, anon;
grant execute on function public.contact_appel_sans_reponse(uuid) to authenticated, service_role;
