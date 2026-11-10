-- LP Promotion branché (10/11/2026, autorisation d'Alex de tester, valider et brancher seul) : premier envoi
-- réel réussi (Quai Sartori, « Nouvelle dénonciation envoyée avec succès »). Une dénonciation par programme,
-- civilité obligatoire, code postal et ville = ville cherchée (exigée à l'envoi), type de bien d'après la fiche.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''accueil'', ''pichet'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''accueil'', ''pichet'')', '''accueil'', ''pichet'', ''lppromotion'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''accueil'', ''pichet'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''accueil'', ''pichet'')', '''accueil'', ''pichet'', ''lppromotion'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('lppromotion', 'lppromotion', true, true, true, now(),
        'Une dénonciation par programme, civilité obligatoire, ville cherchée + CP, type de bien d''après la fiche (10/11/2026)')
on conflict do nothing;
