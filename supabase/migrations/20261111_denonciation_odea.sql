-- ODEA (11/11/2026, décision d'Alex : « le vendeur du client ») : le formulaire « Dénonciation » demande,
-- en plus du client, le nom, l'e-mail et le téléphone du commercial. Le robot y met ceux du vendeur de la
-- fiche, lus dans la fiche vendeur du CRM (dashboard_data.vendeurs). Un vendeur sans e-mail ou sans
-- téléphone dans sa fiche : pas d'ODEA pour ses clients tant que la fiche vendeur n'est pas complétée.
-- Une dénonciation par programme. Compte créé inactif, branché après un premier envoi réel réussi.

create or replace function public.denonciation_vendeur(p_vendeur text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('nom', trim(coalesce(e->>'prenom', '') || ' ' || coalesce(e->>'nom', '')),
                            'email', trim(e->>'email'),
                            'telephone', regexp_replace(coalesce(e->>'telephone', ''), '\D', '', 'g'))
  from public.dashboard_data d, jsonb_array_elements(d.vendeurs) e
  where d.id = 'main' and p_vendeur is not null
    and public.prenom_norm(e->>'prenom') = public.prenom_norm(p_vendeur)
    and coalesce(e->>'email', '') ~ '@'
    and length(regexp_replace(coalesce(e->>'telephone', ''), '\D', '', 'g')) >= 10
  limit 1
$$;
revoke all on function public.denonciation_vendeur(text) from public, anon, authenticated;
grant execute on function public.denonciation_vendeur(text) to service_role;

create or replace function public.robot_contact_vendeur(p_cle text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select public.denonciation_vendeur(c.vendeur) from public.contacts c where c.id = p_id);
end
$$;
revoke all on function public.robot_contact_vendeur(text, uuid) from public;
grant execute on function public.robot_contact_vendeur(text, uuid) to anon, authenticated, service_role;

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('  order by x.compte, x.recu_le' in d) = 0 then raise exception 'fin introuvable (a_faire)'; end if;
  execute replace(d, '  order by x.compte, x.recu_le',
    '    and (x.plateforme <> ''odea'' or public.denonciation_vendeur(c.vendeur) is not null)' || chr(10) ||
    '  order by x.compte, x.recu_le');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('odea', 'odea', false, true, false, null,
        'Une dénonciation par programme ; commercial = vendeur de la fiche (nom, e-mail, téléphone de sa fiche vendeur) (11/11/2026)')
on conflict do nothing;

-- Branché le 11/11/2026 après un essai rempli correctement (sans envoi : aucun client arrivé depuis le
-- branchement ne cherche à Antony ou Bry-sur-Marne). La page a un reCAPTCHA invisible, jamais contourné :
-- si ODEA refuse l'envoi du robot, le registre le montre (échec) et le robot abandonne après 2 essais.
update public.denonciation_comptes set actif = true, valide_le = now() where plateforme = 'odea' and compte = 'odea';
