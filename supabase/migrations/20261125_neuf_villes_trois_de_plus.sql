-- Pages ville : trois villes de plus en ligne.
--
-- APPLIQUÉE le 25/11/2026. Demande d'Alex du 25/11/2026 (« ouvre 3 villes de plus », dit à la session
-- Site, relayé par la mère) ; les trois villes du 92 les plus fournies après Colombes, proposées par Site.
-- Effet immédiat : neuf-prix sert les prix de leurs programmes d'extranet, et le générateur du site
-- peut lire leur JSON avec la clé publique. Pour refermer une ville : la repasser à 'prete'.
--
-- À l'application (pige du 20/11/2026) : Châtenay-Malabry 7 programmes + 1 picking, 237 logements ;
-- Le Plessis-Robinson 10 + 1, 318 ; Puteaux 9 + 2, 307. Quatre villes publiées avec Colombes.

update public.neuf_villes
   set etat = 'publiee'
 where ville in ('Le Plessis-Robinson', 'Puteaux', 'Châtenay-Malabry')
   and etat = 'prete';
