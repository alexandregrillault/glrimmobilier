-- Pages ville : les communes du 78 (Yvelines) entrent dans la liste des villes, à l'état « prete ».
--
-- PRÉPARÉE le 25/11/2026, NON APPLIQUÉE. Demande d'Alex du 25/11/2026, dite à la session Site et
-- relayée par la mère : « on fini le pige et je veux que tu me fasses ça pour tout le 92 puis toute l'IDF ».
--
-- « prete » = le fabricant du site peut préparer la page ; rien n'est en ligne et aucun prix n'est
-- servi tant que la ville n'est pas passée à « publiee ». Même règle que pour le 92 : une commune
-- entre si elle a au moins un programme à montrer (logement libre ou optionné, ou programme « picking »),
-- jamais pour un programme « sans mandat » seul.
--
-- Relevé sur la pige du 25/11/2026 (encore en cours ce jour-là : à recompter avant d'appliquer) :
-- 60 communes, 111 programmes d'extranet et 24 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Achères', '78005', '78', 'prete'),
  ('Andrésy', '78015', '78', 'prete'),
  ('Bailly', '78043', '78', 'prete'),
  ('Bois-d''Arcy', '78073', '78', 'prete'),
  ('Bonnières-sur-Seine', '78089', '78', 'prete'),
  ('Bougival', '78092', '78', 'prete'),
  ('Bréval', '78107', '78', 'prete'),
  ('Buchelay', '78118', '78', 'prete'),
  ('Carrières-sous-Poissy', '78123', '78', 'prete'),
  ('Carrières-sur-Seine', '78124', '78', 'prete'),
  ('Chambourcy', '78133', '78', 'prete'),
  ('Chanteloup-les-Vignes', '78138', '78', 'prete'),
  ('Châteaufort', '78143', '78', 'prete'),
  ('Chatou', '78146', '78', 'prete'),
  ('Chevreuse', '78160', '78', 'prete'),
  ('Ecquevilly', '78206', '78', 'prete'),
  ('Élancourt', '78208', '78', 'prete'),
  ('Fontenay-le-Fleury', '78242', '78', 'prete'),
  ('Gargenville', '78267', '78', 'prete'),
  ('Hardricourt', '78299', '78', 'prete'),
  ('Houdan', '78310', '78', 'prete'),
  ('Jouars-Pontchartrain', '78321', '78', 'prete'),
  ('La Celle-Saint-Cloud', '78126', '78', 'prete'),
  ('Le Chesnay-Rocquencourt', '78158', '78', 'prete'),
  ('Le Mesnil-le-Roi', '78396', '78', 'prete'),
  ('Le Pecq', '78481', '78', 'prete'),
  ('Le Vésinet', '78650', '78', 'prete'),
  ('Limay', '78335', '78', 'prete'),
  ('Magnanville', '78354', '78', 'prete'),
  ('Magny-les-Hameaux', '78356', '78', 'prete'),
  ('Maisons-Laffitte', '78358', '78', 'prete'),
  ('Mantes-la-Jolie', '78361', '78', 'prete'),
  ('Mantes-la-Ville', '78362', '78', 'prete'),
  ('Marly-le-Roi', '78372', '78', 'prete'),
  ('Maurepas', '78383', '78', 'prete'),
  ('Méré', '78389', '78', 'prete'),
  ('Meulan-en-Yvelines', '78401', '78', 'prete'),
  ('Montesson', '78418', '78', 'prete'),
  ('Neauphle-le-Château', '78442', '78', 'prete'),
  ('Noisy-le-Roi', '78455', '78', 'prete'),
  ('Orgeval', '78466', '78', 'prete'),
  ('Plaisir', '78490', '78', 'prete'),
  ('Poissy', '78498', '78', 'prete'),
  ('Rambouillet', '78517', '78', 'prete'),
  ('Rosny-sur-Seine', '78531', '78', 'prete'),
  ('Saint-Arnoult-en-Yvelines', '78537', '78', 'prete'),
  ('Saint-Cyr-l''École', '78545', '78', 'prete'),
  ('Saint-Germain-en-Laye', '78551', '78', 'prete'),
  ('Sartrouville', '78586', '78', 'prete'),
  ('Thiverval-Grignon', '78615', '78', 'prete'),
  ('Thoiry', '78616', '78', 'prete'),
  ('Toussus-le-Noble', '78620', '78', 'prete'),
  ('Triel-sur-Seine', '78624', '78', 'prete'),
  ('Vélizy-Villacoublay', '78640', '78', 'prete'),
  ('Verneuil-sur-Seine', '78642', '78', 'prete'),
  ('Vernouillet', '78643', '78', 'prete'),
  ('Versailles', '78646', '78', 'prete'),
  ('Villennes-sur-Seine', '78672', '78', 'prete'),
  ('Viroflay', '78686', '78', 'prete'),
  ('Voisins-le-Bretonneux', '78688', '78', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;
