-- Pages ville : les communes du 91 (Essonne) entrent dans la liste des villes, à l'état « prete ».
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
-- 40 communes, 79 programmes d'extranet et 15 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Arpajon', '91021', '91', 'prete'),
  ('Ballainvilliers', '91044', '91', 'prete'),
  ('Ballancourt-sur-Essonne', '91045', '91', 'prete'),
  ('Bondoufle', '91086', '91', 'prete'),
  ('Bouray-sur-Juine', '91095', '91', 'prete'),
  ('Brétigny-sur-Orge', '91103', '91', 'prete'),
  ('Brunoy', '91114', '91', 'prete'),
  ('Bures-sur-Yvette', '91122', '91', 'prete'),
  ('Chilly-Mazarin', '91161', '91', 'prete'),
  ('Corbeil-Essonnes', '91174', '91', 'prete'),
  ('Dourdan', '91200', '91', 'prete'),
  ('Draveil', '91201', '91', 'prete'),
  ('Égly', '91207', '91', 'prete'),
  ('Étampes', '91223', '91', 'prete'),
  ('Évry-Courcouronnes', '91228', '91', 'prete'),
  ('Gif-sur-Yvette', '91272', '91', 'prete'),
  ('Grigny', '91286', '91', 'prete'),
  ('Igny', '91312', '91', 'prete'),
  ('Juvisy-sur-Orge', '91326', '91', 'prete'),
  ('Le Plessis-Pâté', '91494', '91', 'prete'),
  ('Longjumeau', '91345', '91', 'prete'),
  ('Longpont-sur-Orge', '91347', '91', 'prete'),
  ('Massy', '91377', '91', 'prete'),
  ('Mennecy', '91386', '91', 'prete'),
  ('Montgeron', '91421', '91', 'prete'),
  ('Montlhéry', '91425', '91', 'prete'),
  ('Morsang-sur-Orge', '91434', '91', 'prete'),
  ('Ollainville', '91461', '91', 'prete'),
  ('Ormoy', '91468', '91', 'prete'),
  ('Orsay', '91471', '91', 'prete'),
  ('Palaiseau', '91477', '91', 'prete'),
  ('Quincy-sous-Sénart', '91514', '91', 'prete'),
  ('Ris-Orangis', '91521', '91', 'prete'),
  ('Saclay', '91534', '91', 'prete'),
  ('Saint-Germain-lès-Arpajon', '91552', '91', 'prete'),
  ('Sainte-Geneviève-des-Bois', '91549', '91', 'prete'),
  ('Saintry-sur-Seine', '91577', '91', 'prete'),
  ('Vigneux-sur-Seine', '91657', '91', 'prete'),
  ('Viry-Châtillon', '91687', '91', 'prete'),
  ('Wissous', '91689', '91', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;
