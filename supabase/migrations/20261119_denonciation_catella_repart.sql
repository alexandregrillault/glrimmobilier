-- Catella : la file d'attente est abandonnée, le robot ne dénonce plus que les
-- clients reçus à partir du 19/11/2026 à 14 h 45 (décision d'Alex du 19/11/2026 :
-- « abandonne ceux de la file d'attente, fais uniquement ceux qui arrivent à partir
-- de maintenant »). Le retard venait des 17 et 18/11, sans passage Catella.
--
-- denonciation_comptes.valide_le était une date (jour entier) : elle devient une
-- date avec heure, pour pouvoir dire « à partir de maintenant ». Les autres comptes
-- gardent exactement la même valeur (minuit du jour de leur branchement).
-- robot_denonciations_a_faire_plateformes compare déjà recu_le à valide_le : rien
-- d'autre à changer. Aucune ligne de « denonciations » n'est touchée.

alter table public.denonciation_comptes
  alter column valide_le type timestamptz using valide_le::timestamptz;

update public.denonciation_comptes
   set valide_le = timestamptz '2026-11-19 14:45:00+01',
       note = coalesce(note, '') || ' ; file abandonnée le 19/11/2026 à 14 h 45 : seulement les clients reçus après (décision d''Alex)'
 where plateforme = 'catella' and compte = 'catella';
