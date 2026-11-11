-- ODEA refuse le robot (11/11/2026, premier vrai envoi, fiche de test « Enzo Chopard » créée à la demande
-- d'Alex) : le formulaire répond « You must be a human to submit this form » (reCAPTCHA invisible). On ne
-- contourne jamais une protection anti-robot : ODEA est éteint et redevient une dénonciation à la main.
update public.denonciation_comptes
   set actif = false,
       note = coalesce(note, '') || ' ; ARRÊTÉ le 11/11/2026 : reCAPTCHA « You must be a human », dénonciation à la main'
 where plateforme = 'odea';
