-- Pirphi branché le 12/11/2026 : décision d'Alex, « Ajouter un nouveau client » (Mon compte) vaut dénonciation.
-- Le vrai envoi du 11/11 (fiche de test Enzo Chopard) avait bien créé le client (fiche 3619) mais était noté
-- « échec » faute de liste où le retrouver : corrigé. Preuve désormais = la page de la fiche client créée.
update public.denonciation_comptes
   set actif = true, valide_le = now(),
       note = 'Un client par client : « Ajouter un nouveau client » vaut dénonciation (décision d''Alex du 12/11/2026), civilité obligatoire'
 where plateforme = 'pirphi';
update public.denonciations
   set statut = 'envoyee', detail = 'Pirphi : client créé le 11/11/2026 (fiche 3619), noté échec à tort puis corrigé le 12/11/2026'
 where compte = 'pirphi' and contact_id = 'bf7df9cb-4def-4ab0-b4fb-bf05cf97bad9' and statut = 'echec';
