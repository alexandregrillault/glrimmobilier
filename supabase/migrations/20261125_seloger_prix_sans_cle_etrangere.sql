-- seloger_prix : retirer la clé étrangère vers pige_programmes, qui bloque l'import de la pige.
--
-- PAS ENCORE APPLIQUÉE (préparée le 25/11/2026, en attente de l'accord d'Alex).
--
-- Pourquoi : à chaque pige, pige_import_from_brut() vide pige_lots et pige_programmes par un
-- « truncate » avant de les remplir. Postgres refuse de vider ainsi une table vers laquelle pointe
-- une clé étrangère d'une autre table, même si aucune ligne ne s'en sert. Depuis la création de
-- seloger_prix (20/11/2026), seloger_prix.programme_id pointe vers pige_programmes : la pige du
-- 25/11/2026 n'a donc pas pu être importée (la base est restée sur celle du 20/11).
--
-- Ce que fait cette migration : elle retire seulement la contrainte. La colonne programme_id, son
-- index et toutes les lignes restent. Vérifié le 25/11/2026 : les 341 lignes de seloger_prix ont
-- programme_id vide ; aucune fonction, aucune vue et aucune page du CRM ou du site ne lit cette table
-- en passant par la contrainte.
--
-- Ce que ça change : programme_id devient une simple référence, que la base ne contrôle plus.
-- Si un programme disparaît de la pige, la valeur reste telle quelle dans seloger_prix (avant, elle
-- aurait été vidée) : qui la lit doit accepter qu'elle ne mène plus à rien (jointure « left join »).

alter table public.seloger_prix drop constraint if exists seloger_prix_programme_id_fkey;

comment on column public.seloger_prix.programme_id is
  'Identifiant du programme dans pige_programmes. Simple référence, sans clé étrangère (retirée le 25/11/2026 : elle bloquait le truncate de l''import de la pige) ; peut ne plus exister après une pige.';
