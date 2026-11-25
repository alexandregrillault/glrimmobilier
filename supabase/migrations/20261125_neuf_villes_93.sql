-- Pages ville : les communes du 93 (Seine-Saint-Denis) entrent dans la liste des villes, à l'état « prete ».
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
-- 31 communes, 160 programmes d'extranet et 26 « picking ». Codes INSEE : geo.api.gouv.fr.
-- Aucune donnée existante n'est modifiée ; une commune déjà présente est laissée telle quelle.

insert into public.neuf_villes (ville, insee, dept, etat, slug)
select x.ville, x.insee, x.dept, x.etat, public.neuf_slug(x.ville)
  from (values
  ('Aubervilliers', '93001', '93', 'prete'),
  ('Aulnay-sous-Bois', '93005', '93', 'prete'),
  ('Bagnolet', '93006', '93', 'prete'),
  ('Bobigny', '93008', '93', 'prete'),
  ('Bondy', '93010', '93', 'prete'),
  ('Clichy-sous-Bois', '93014', '93', 'prete'),
  ('Drancy', '93029', '93', 'prete'),
  ('Dugny', '93030', '93', 'prete'),
  ('Épinay-sur-Seine', '93031', '93', 'prete'),
  ('Gagny', '93032', '93', 'prete'),
  ('L''Île-Saint-Denis', '93039', '93', 'prete'),
  ('La Courneuve', '93027', '93', 'prete'),
  ('Le Blanc-Mesnil', '93007', '93', 'prete'),
  ('Les Lilas', '93045', '93', 'prete'),
  ('Livry-Gargan', '93046', '93', 'prete'),
  ('Montfermeil', '93047', '93', 'prete'),
  ('Montreuil', '93048', '93', 'prete'),
  ('Neuilly-Plaisance', '93049', '93', 'prete'),
  ('Neuilly-sur-Marne', '93050', '93', 'prete'),
  ('Noisy-le-Grand', '93051', '93', 'prete'),
  ('Noisy-le-Sec', '93053', '93', 'prete'),
  ('Pantin', '93055', '93', 'prete'),
  ('Romainville', '93063', '93', 'prete'),
  ('Rosny-sous-Bois', '93064', '93', 'prete'),
  ('Saint-Denis', '93066', '93', 'prete'),
  ('Saint-Ouen-sur-Seine', '93070', '93', 'prete'),
  ('Sevran', '93071', '93', 'prete'),
  ('Stains', '93072', '93', 'prete'),
  ('Villemomble', '93077', '93', 'prete'),
  ('Villepinte', '93078', '93', 'prete'),
  ('Villetaneuse', '93079', '93', 'prete')
  ) as x (ville, insee, dept, etat)
on conflict (ville) do nothing;

-- Pierrefitte-sur-Seine a fusionné avec Saint-Denis le 01/01/2025 (elle n'est plus dans la liste
-- officielle des communes) : son programme est rangé sur la page de Saint-Denis (« fais comme tu le
-- sens », Alex, 25/11/2026). Demande la colonne pige_villes, créée par
-- 20261125_neuf_arrondissements_et_compteurs.sql, à appliquer avant ce fichier.
update public.neuf_villes
   set pige_villes = array['Saint-Denis', 'Pierrefitte-sur-Seine']
 where ville = 'Saint-Denis' and dept = '93';
