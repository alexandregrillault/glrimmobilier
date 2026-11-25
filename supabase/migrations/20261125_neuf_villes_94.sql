-- Pages ville : les communes du 94 (Val-de-Marne) entrent dans la liste des villes, à l'état « prete ».
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
-- 36 communes, 155 programmes d'extranet et 29 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Alfortville', '94002', '94', 'prete'),
  ('Arcueil', '94003', '94', 'prete'),
  ('Boissy-Saint-Léger', '94004', '94', 'prete'),
  ('Bry-sur-Marne', '94015', '94', 'prete'),
  ('Cachan', '94016', '94', 'prete'),
  ('Champigny-sur-Marne', '94017', '94', 'prete'),
  ('Chennevières-sur-Marne', '94019', '94', 'prete'),
  ('Chevilly-Larue', '94021', '94', 'prete'),
  ('Choisy-le-Roi', '94022', '94', 'prete'),
  ('Créteil', '94028', '94', 'prete'),
  ('Fontenay-sous-Bois', '94033', '94', 'prete'),
  ('Gentilly', '94037', '94', 'prete'),
  ('Ivry-sur-Seine', '94041', '94', 'prete'),
  ('Joinville-le-Pont', '94042', '94', 'prete'),
  ('L''Haÿ-les-Roses', '94038', '94', 'prete'),
  ('La Queue-en-Brie', '94060', '94', 'prete'),
  ('Le Kremlin-Bicêtre', '94043', '94', 'prete'),
  ('Le Perreux-sur-Marne', '94058', '94', 'prete'),
  ('Le Plessis-Trévise', '94059', '94', 'prete'),
  ('Limeil-Brévannes', '94044', '94', 'prete'),
  ('Maisons-Alfort', '94046', '94', 'prete'),
  ('Nogent-sur-Marne', '94052', '94', 'prete'),
  ('Noiseau', '94053', '94', 'prete'),
  ('Orly', '94054', '94', 'prete'),
  ('Ormesson-sur-Marne', '94055', '94', 'prete'),
  ('Saint-Mandé', '94067', '94', 'prete'),
  ('Saint-Maur-des-Fossés', '94068', '94', 'prete'),
  ('Saint-Maurice', '94069', '94', 'prete'),
  ('Sucy-en-Brie', '94071', '94', 'prete'),
  ('Thiais', '94073', '94', 'prete'),
  ('Valenton', '94074', '94', 'prete'),
  ('Villejuif', '94076', '94', 'prete'),
  ('Villeneuve-Saint-Georges', '94078', '94', 'prete'),
  ('Villiers-sur-Marne', '94079', '94', 'prete'),
  ('Vincennes', '94080', '94', 'prete'),
  ('Vitry-sur-Seine', '94081', '94', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;
