-- Esprit Valmy : visite 3D en version « plan 3D qu'on fait tourner » (dossier 8db4aeab0032-d/ de plans3d).
-- Cible changée le 27/11/2026 de -c/ vers -d/ : retouche demandée par Alex à Plans 3D (logement posé sur une
-- parcelle, sans décor ; noms des pièces en petit ; surface totale dans un angle). -c/ reste en place, non servi.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE : à lancer au signal de la session mère, avec le « déploie » final
-- d'Alex. Version voulue par Alex et livrée par Plans 3D : sans visite pièce par pièce, 1,1 à 1,5 Mo par
-- logement au lieu de 4,5 à 6,6. Les dossiers 8db4aeab0032/, -b/ et -c/ restent en place.
-- Rien n'est supprimé.
--
-- Retour arrière : update public.neuf_visites_3d set fichier = replace(fichier, '8db4aeab0032-d/', '8db4aeab0032-b/')
--                   where programme_id = 'marignan:130';

update public.neuf_visites_3d
   set fichier = replace(fichier, '8db4aeab0032-b/', '8db4aeab0032-d/')
 where programme_id = 'marignan:130'
   and fichier like '8db4aeab0032-b/%';
