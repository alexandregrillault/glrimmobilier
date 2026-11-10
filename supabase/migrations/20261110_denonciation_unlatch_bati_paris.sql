-- Branchement d'Unlatch, espace Bati Paris (10/11/2026, « valide » puis « Oui, branche » d'Alex) :
-- premier envoi réel réussi (Aziz, IRIS), retrouvé dans les dénonciations de l'espace.
-- Règle Unlatch (décision d'Alex du 10/11) : une dénonciation par client et par espace, qui coche tous
-- les programmes de l'espace dans les villes cherchées par le client (+ zone de recherche = départements
-- quand l'espace en a une) ; « Non » aux sollicitations commerciales par mail et par SMS.
-- Chaque espace règle son propre formulaire : on n'active un espace qu'après son propre essai.
update public.denonciation_comptes
set note = 'Une dénonciation par client : tous les programmes de ses villes cochés, zone de recherche si présente, Non aux sollicitations (décision d''Alex, 10/11/2026)'
where plateforme = 'unlatch';

update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'unlatch' and compte = 'unlatch_bati-paris';
