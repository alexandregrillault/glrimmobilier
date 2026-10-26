-- 26/10/2026 — Liste des lots sans plan pour les scripts d'import de documents.
--
-- Pourquoi : scripts/immolead_plans.js (pige, onglet Chrome sur immo-lead.com, sans session
-- GLR) lisait directement pige_lots avec la clé anonyme pour savoir quels plans aller chercher.
-- La migration 20261026_pige_lecture_privee.sql ferme cette lecture. Cette fonction rend au
-- script uniquement ce dont il a besoin, et rien de plus : identifiant, numéro et type des lots
-- d'une source qui n'ont pas encore de plan. Ni prix, ni commission, ni détail de programme.
--
-- À appliquer AVANT 20261026_pige_lecture_privee.sql, en même temps que la nouvelle version
-- du script (qui appelle cette fonction au lieu de lire pige_lots).

create or replace function public.lots_sans_plan(p_source text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'n', l.n, 'type', l.type, 'programme_id', l.programme_id) order by l.id), '[]'::jsonb)
  from public.pige_lots l
  left join public.documents_lot d on d.lot_id = l.id and d.plan_url is not null
  where p_source ~ '^[a-z0-9_]+$'                      -- une source précise (ex. immolead_wemo), jamais un motif
    and l.programme_id like p_source || ':%'
    and d.lot_id is null
$$;

revoke all on function public.lots_sans_plan(text) from public;
grant execute on function public.lots_sans_plan(text) to anon, authenticated, service_role;

-- Retour arrière :
-- drop function public.lots_sans_plan(text);
