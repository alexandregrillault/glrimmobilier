-- European Homes (11/11/2026, autorisation d'Alex de tester, valider et brancher seul) : Club EH (Axessia),
-- « Contacts » → « DÉNONCER ». Une dénonciation par programme, civilité obligatoire (liste du formulaire),
-- ville et code postal cherchés (cp_obligatoire pour que le robot les reçoive). Compte créé inactif,
-- branché après un essai réussi.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''lppromotion'', ''saintagne'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''lppromotion'', ''saintagne'')', '''lppromotion'', ''saintagne'', ''europeanhomes'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''lppromotion'', ''saintagne'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''lppromotion'', ''saintagne'')', '''lppromotion'', ''saintagne'', ''europeanhomes'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('europeanhomes', 'europeanhomes', true, true, false, null,
        'Une dénonciation par programme, civilité obligatoire, ville et code postal cherchés (11/11/2026)')
on conflict do nothing;

-- Branché le 11/11/2026 après deux essais remplis correctement (Gif-sur-Yvette, puis Longueville, en bas
-- d'une liste de 60 programmes qui se charge en défilant). Pas d'envoi réel d'essai : aucun client arrivé
-- depuis le branchement ne cherche dans ces villes ; la preuve sera le client retrouvé dans « Mes contacts ».
update public.denonciation_comptes set actif = true, valide_le = now() where plateforme = 'europeanhomes';
