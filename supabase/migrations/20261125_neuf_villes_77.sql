-- Pages ville : les communes du 77 (Seine-et-Marne) entrent dans la liste des villes, à l'état « prete ».
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
-- 48 communes, 81 programmes d'extranet et 19 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Avon', '77014', '77', 'prete'),
  ('Boissise-le-Roi', '77040', '77', 'prete'),
  ('Brou-sur-Chantereine', '77055', '77', 'prete'),
  ('Bussy-Saint-Georges', '77058', '77', 'prete'),
  ('Champs-sur-Marne', '77083', '77', 'prete'),
  ('Chanteloup-en-Brie', '77085', '77', 'prete'),
  ('Chelles', '77108', '77', 'prete'),
  ('Chessy', '77111', '77', 'prete'),
  ('Combs-la-Ville', '77122', '77', 'prete'),
  ('Coupvray', '77132', '77', 'prete'),
  ('Crécy-la-Chapelle', '77142', '77', 'prete'),
  ('Dammarie-les-Lys', '77152', '77', 'prete'),
  ('Dampmart', '77155', '77', 'prete'),
  ('Faremoutiers', '77176', '77', 'prete'),
  ('Fontainebleau', '77186', '77', 'prete'),
  ('Fontenay-Trésigny', '77192', '77', 'prete'),
  ('Gretz-Armainvilliers', '77215', '77', 'prete'),
  ('Isles-lès-Villenoy', '77232', '77', 'prete'),
  ('La Chapelle-la-Reine', '77088', '77', 'prete'),
  ('La Rochette', '77389', '77', 'prete'),
  ('Lagny-sur-Marne', '77243', '77', 'prete'),
  ('Lieusaint', '77251', '77', 'prete'),
  ('Lizy-sur-Ourcq', '77257', '77', 'prete'),
  ('Lognes', '77258', '77', 'prete'),
  ('Longueville', '77260', '77', 'prete'),
  ('Magny-le-Hongre', '77268', '77', 'prete'),
  ('Meaux', '77284', '77', 'prete'),
  ('Melun', '77288', '77', 'prete'),
  ('Messy', '77292', '77', 'prete'),
  ('Moissy-Cramayel', '77296', '77', 'prete'),
  ('Montereau-Fault-Yonne', '77305', '77', 'prete'),
  ('Montévrain', '77307', '77', 'prete'),
  ('Moussy-le-Neuf', '77322', '77', 'prete'),
  ('Moussy-le-Vieux', '77323', '77', 'prete'),
  ('Nangis', '77327', '77', 'prete'),
  ('Noisiel', '77337', '77', 'prete'),
  ('Ozoir-la-Ferrière', '77350', '77', 'prete'),
  ('Pomponne', '77372', '77', 'prete'),
  ('Provins', '77379', '77', 'prete'),
  ('Roissy-en-Brie', '77390', '77', 'prete'),
  ('Saint-Fargeau-Ponthierry', '77407', '77', 'prete'),
  ('Saint-Thibault-des-Vignes', '77438', '77', 'prete'),
  ('Savigny-le-Temple', '77445', '77', 'prete'),
  ('Serris', '77449', '77', 'prete'),
  ('Torcy', '77468', '77', 'prete'),
  ('Trilport', '77475', '77', 'prete'),
  ('Vaires-sur-Marne', '77479', '77', 'prete'),
  ('Villevaudé', '77517', '77', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;
