-- 26/10/2026 — Fin de la lecture publique de la pige et des documents.
--
-- Pourquoi : avec la clé anonyme (publique, présente dans le code des pages), n'importe qui
-- pouvait télécharger les 1 414 programmes pigés (commissions comprises), les 19 798 lots
-- avec leurs prix, les archives de pige et la liste des plans/plaquettes.
-- Désormais seuls les comptes connectés (gérants et commerciaux) lisent ces tables.
--
-- Ce qui continue de fonctionner sans compte, parce que ça passe par des fonctions
-- SECURITY DEFINER ou par les edge functions (clé service_role), que les policies ne
-- concernent pas : page programme publique (programme_public), feuille sélection client
-- (edge function selection), plaquette (plaquette_stats), état des documents pour les
-- scripts d'import (docs_etat_source_json).
--
-- Volontairement inchangé : pige_brut (insertion anonyme utilisée par le push
-- hebdomadaire de la pige depuis Chrome, scripts/push_page.js).
--
-- Prérequis : la carte du CRM doit être la version qui lit la session (carte.html du
-- 26/10/2026, données via pige_carte() et documents avec la session « glr_session »).
--
-- Aucune donnée n'est modifiée : seuls les droits de lecture changent, donc pas de
-- sauvegarde de table. Retour arrière en bas du fichier.

begin;

-- 1. Les policies de lecture visaient « public » (anonymes compris) : on les restreint
--    aux comptes connectés, sans changer leur condition.
alter policy pige_programmes_lecture     on public.pige_programmes     to authenticated;
alter policy pige_lots_lecture           on public.pige_lots           to authenticated;
alter policy pige_archives_lecture       on public.pige_archives       to authenticated;
alter policy documents_lot_lecture       on public.documents_lot       to authenticated;
alter policy documents_programme_lecture on public.documents_programme to authenticated;

-- 2. Ceinture et bretelles : le rôle anonyme n'a plus aucun droit sur ces tables, même si
--    une policy trop large réapparaissait un jour.
revoke all on public.pige_programmes, public.pige_lots, public.pige_archives,
              public.documents_lot, public.documents_programme
  from anon;

commit;

-- Contrôle après application (attendu : anon_lecture = false partout, policies → authenticated) :
-- select c.relname, has_table_privilege('anon', c.oid, 'SELECT') as anon_lecture,
--        (select string_agg(p.policyname || ' → ' || array_to_string(p.roles, ','), ' ; ')
--           from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policies
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public'
--   and c.relname in ('pige_programmes','pige_lots','pige_archives','documents_lot','documents_programme');

-- Retour arrière (remet exactement l'état du 26/10/2026 avant migration) :
-- begin;
-- alter policy pige_programmes_lecture     on public.pige_programmes     to public;
-- alter policy pige_lots_lecture           on public.pige_lots           to public;
-- alter policy pige_archives_lecture       on public.pige_archives       to public;
-- alter policy documents_lot_lecture       on public.documents_lot       to public;
-- alter policy documents_programme_lecture on public.documents_programme to public;
-- grant select, insert, update, delete, truncate, references, trigger
--   on public.pige_programmes, public.pige_lots, public.pige_archives,
--      public.documents_lot, public.documents_programme
--   to anon;
-- commit;
