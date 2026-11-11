-- Concilio, Inovefa, Pirphi (11/11/2026, autorisation d'Alex de tester, valider et brancher seul) : formulaires
-- trouvés par l'exploration complète de leurs extranets (le premier repérage n'avait rien vu).
-- Concilio (Expert-CRM) : « Prospects dénoncés » → « Dénoncer un prospect », civilité obligatoire, une
--   dénonciation par programme, e-mail et téléphone dans le message (pas de case prévue).
-- Inovefa : page du programme → « Dénoncer un prospect » → e-mail « Vérifier » → prénom, nom, téléphone, ville ;
--   une dénonciation par programme ; e-mail déjà connu d'Inovefa = « déjà connu ».
-- Pirphi : « Mon compte » → « Ajouter un nouveau client » (civilité obligatoire), une fois par client.
-- Concilio branché après un vrai envoi réussi (fiche de test « Enzo Chopard », demande d'Alex) ; Inovefa et
-- Pirphi créés éteints, allumés après leur vrai envoi.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''duval'', ''ogic'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''duval'', ''ogic'')', '''duval'', ''ogic'', ''concilio'', ''pirphi'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''duval'', ''ogic'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''duval'', ''ogic'')', '''duval'', ''ogic'', ''concilio'', ''pirphi'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('concilio', 'concilio', false, true, true, now(), 'Une dénonciation par programme, civilité obligatoire, e-mail et téléphone dans le message (11/11/2026)'),
       ('inovefa', 'inovefa', false, true, false, null, 'Une dénonciation par programme : e-mail « Vérifier », puis fiche (11/11/2026)'),
       ('pirphi', 'pirphi', false, false, false, null, 'Un client par client (« Ajouter un nouveau client »), civilité obligatoire (11/11/2026)')
on conflict do nothing;

-- Même jour, après les vrais envois de test : Inovefa envoie et retrouve le client → allumé. Pirphi : « Ajouter un
-- nouveau client » ouvre un dossier de réservation (personnes physiques, situation, « Transférer ») qui reste dans
-- notre espace tant qu'il n'est pas transféré complet : ce n'est pas une dénonciation, Pirphi reste éteint.
update public.denonciation_comptes set actif = true, valide_le = now() where plateforme = 'inovefa';
update public.denonciation_comptes
   set note = 'PAS une dénonciation : « Ajouter un nouveau client » ouvre un dossier de réservation à transférer (11/11/2026) ; reste à la main'
 where plateforme = 'pirphi';
