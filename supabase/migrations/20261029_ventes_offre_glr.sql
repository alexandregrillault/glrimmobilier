-- Offre GLR sur une vente (demande d'Alex du 29/10/2026)
-- Geste commercial payé par GLR à l'acquéreur (ticket cadeau…), en euros.
-- Jamais sur la facture au promoteur : `honoraires` reste le montant facturé.
-- Ce que GLR gagne vraiment = honoraires − offre ; la commission du vendeur
-- est calculée sur ce net : (honoraires − offre) × taux.

-- 1. Sauvegarde des fonctions modifiées
create table if not exists public.fonctions_backup_20261029 as
select p.proname, pg_get_functiondef(p.oid) as definition, now() as sauve_le
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('facture_commerciale_emettre', 'classement_commerciaux', 'perf_vendeurs', 'perf_mensuel', 'rapport_activite');
alter table public.fonctions_backup_20261029 enable row level security;
revoke all on public.fonctions_backup_20261029 from anon, authenticated;
grant all on public.fonctions_backup_20261029 to service_role;

-- 2. La colonne
alter table public.ventes add column if not exists "offreGlr" numeric(12,2);
alter table public.ventes add constraint ventes_offre_glr_positive check ("offreGlr" is null or "offreGlr" >= 0);
comment on column public.ventes."offreGlr" is 'Offre GLR à l''acquéreur (€), déduite de nos honoraires et de la base de commission du vendeur ; jamais sur la facture promoteur.';

-- 3. Les fonctions : chiffre d'affaires et commission en net de l'offre
do $$
declare f text; def text; neuf text;
begin
  -- classements et pilotage : sum(v.honoraires) → sum(honoraires − offre)
  foreach f in array array['classement_commerciaux', 'perf_vendeurs', 'perf_mensuel', 'rapport_activite'] loop
    select pg_get_functiondef(('public.' || f)::regproc) into def;
    neuf := replace(def, 'sum(v.honoraires)', 'sum(v.honoraires - coalesce(v."offreGlr", 0))');
    if neuf = def then raise exception 'Rien à remplacer dans %', f; end if;
    execute neuf;
  end loop;

  -- facture de commission du vendeur : base = honoraires − offre, et l'offre gardée dans l'instantané de la vente
  select pg_get_functiondef('public.facture_commerciale_emettre'::regproc) into def;
  neuf := replace(def,
    'comm := round(coalesce(v.honoraires, 0) * coalesce(v.taux, 0) / 100, 2);',
    'comm := round(greatest(coalesce(v.honoraires, 0) - coalesce(v."offreGlr", 0), 0) * coalesce(v.taux, 0) / 100, 2);');
  neuf := replace(neuf, '''honoraires'', v.honoraires,', '''honoraires'', v.honoraires, ''offreGlr'', v."offreGlr",');
  if neuf = def or position('offreGlr", 0), 0)' in neuf) = 0 or position('''offreGlr'', v."offreGlr"' in neuf) = 0 then
    raise exception 'facture_commerciale_emettre : remplacement incomplet';
  end if;
  execute neuf;
end $$;
