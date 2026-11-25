-- Pages ville : les communes du 95 (Val-d'Oise) entrent dans la liste des villes, à l'état « prete ».
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
-- 32 communes, 69 programmes d'extranet et 12 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Andilly', '95014', '95', 'prete'),
  ('Argenteuil', '95018', '95', 'prete'),
  ('Arnouville', '95019', '95', 'prete'),
  ('Baillet-en-France', '95042', '95', 'prete'),
  ('Beauchamp', '95051', '95', 'prete'),
  ('Bezons', '95063', '95', 'prete'),
  ('Bouffémont', '95091', '95', 'prete'),
  ('Cergy', '95127', '95', 'prete'),
  ('Cormeilles-en-Parisis', '95176', '95', 'prete'),
  ('Deuil-la-Barre', '95197', '95', 'prete'),
  ('Domont', '95199', '95', 'prete'),
  ('Enghien-les-Bains', '95210', '95', 'prete'),
  ('Ermont', '95219', '95', 'prete'),
  ('Gonesse', '95277', '95', 'prete'),
  ('Goussainville', '95280', '95', 'prete'),
  ('Jouy-le-Moutier', '95323', '95', 'prete'),
  ('La Frette-sur-Seine', '95257', '95', 'prete'),
  ('Le Plessis-Bouchard', '95491', '95', 'prete'),
  ('Louvres', '95351', '95', 'prete'),
  ('Luzarches', '95352', '95', 'prete'),
  ('Méry-sur-Oise', '95394', '95', 'prete'),
  ('Montigny-lès-Cormeilles', '95424', '95', 'prete'),
  ('Montmorency', '95428', '95', 'prete'),
  ('Osny', '95476', '95', 'prete'),
  ('Pontoise', '95500', '95', 'prete'),
  ('Puiseux-en-France', '95509', '95', 'prete'),
  ('Saint-Leu-la-Forêt', '95563', '95', 'prete'),
  ('Saint-Martin-du-Tertre', '95566', '95', 'prete'),
  ('Sannois', '95582', '95', 'prete'),
  ('Soisy-sous-Montmorency', '95598', '95', 'prete'),
  ('Survilliers', '95604', '95', 'prete'),
  ('Taverny', '95607', '95', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;
