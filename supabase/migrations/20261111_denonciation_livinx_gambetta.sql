-- Immo-Lead : Livinx et Gambetta branchés le 11/11/2026 (autorisation d'Alex de tester, valider et brancher
-- seul), après un essai rempli puis un vrai envoi réussi chacun (Les Hydrangeas, Rueil ; Majestic, L'Haÿ).
-- Même parcours que Care : « Suivant » ouvre la fiche, programme obligatoire, « Enregistrer le contact ».
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('immolead', 'livinx', false, true, true, now(), 'Branché le 11/11/2026 après un vrai envoi réussi'),
       ('immolead', 'gambetta', false, true, true, now(), 'Branché le 11/11/2026 après un vrai envoi réussi')
on conflict do nothing;
