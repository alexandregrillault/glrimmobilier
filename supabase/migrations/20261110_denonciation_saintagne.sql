-- Saint Agne branché (10/11/2026, autorisation d'Alex de tester, valider et brancher seul) : premier envoi
-- réel réussi (Coeur Carnot, « Demande acceptée »). Une dénonciation par programme (le message nomme le
-- programme), civilité obligatoire.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''pichet'', ''lppromotion'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''pichet'', ''lppromotion'')', '''pichet'', ''lppromotion'', ''saintagne'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''pichet'', ''lppromotion'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''pichet'', ''lppromotion'')', '''pichet'', ''lppromotion'', ''saintagne'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('saintagne', 'saintagne', false, true, true, now(),
        'Une dénonciation par programme (message qui nomme le programme), civilité obligatoire (10/11/2026)')
on conflict do nothing;
