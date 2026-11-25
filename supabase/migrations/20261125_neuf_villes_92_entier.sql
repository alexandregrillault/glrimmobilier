-- Pages ville : tout le 92 en ligne.
--
-- PRÉPARÉE le 25/11/2026, NON APPLIQUÉE : à appliquer seulement quand la pige du jour est finie
-- (signal de la mère). Demande d'Alex du 25/11/2026, dite à la session Site et relayée par la mère :
-- « on fini le pige et je veux que tu me fasses ça pour tout le 92 puis toute l'IDF ».
--
-- Passe à « publiee » les 30 communes du 92 encore à l'état « prete » (Colombes, Le Plessis-Robinson,
-- Puteaux et Châtenay-Malabry le sont déjà) : 34 communes en ligne. Effet immédiat : neuf-prix sert
-- les prix de leurs programmes d'extranet et le générateur du site lit leur JSON avec la clé publique.
-- Pour refermer une ville : la repasser à 'prete'.
--
-- Vérifié sur la pige du 25/11/2026 : les 34 communes ont chacune au moins un programme à montrer
-- (Châtillon : un « picking » seulement). Vaucresson et Marnes-la-Coquette n'ont aucun programme
-- en base, même « picking » : elles ne sont pas ajoutées.

update public.neuf_villes
   set etat = 'publiee'
 where dept = '92'
   and etat = 'prete';
