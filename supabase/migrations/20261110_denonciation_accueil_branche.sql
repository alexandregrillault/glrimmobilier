-- Accueil Immobilier branché (10/11/2026, « Valide » d'Alex) : premier envoi réel réussi (client de
-- Colombes, Carré Caillebotte), retrouvé dans « Mes dénonciations ».
update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'accueil' and compte = 'accueil';
