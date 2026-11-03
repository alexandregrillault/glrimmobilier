-- TVA de la vente : 20 % ou 5,5 % (demande d'Alex du 03/11/2026)
-- Certains lots se vendent en TVA réduite (zone ANRU / QPV, acquéreur éligible).
-- La fenêtre « Vendu » propose les deux prix ; le choix part dans
-- contacts.vente_lot.tva et la vente le garde dans ventes."tva".
-- Décision d'Alex du 03/11/2026 : les honoraires se calculent sur le prix
-- réellement payé, donc `prix` = prix TVA 5,5 % quand la vente est en 5,5 %.
-- Ventes existantes et ancien CRM : 20 % par défaut.

-- 1. Sauvegarde de la fonction modifiée
create table if not exists public.fonctions_backup_20261103 as
select p.proname, pg_get_functiondef(p.oid) as definition, now() as sauve_le
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'vente_depuis_fiche';
alter table public.fonctions_backup_20261103 enable row level security;
revoke all on public.fonctions_backup_20261103 from anon, authenticated;
grant all on public.fonctions_backup_20261103 to service_role;

-- 2. La colonne
alter table public.ventes add column if not exists "tva" numeric(3,1) not null default 20;
alter table public.ventes add constraint ventes_tva_valeurs check ("tva" in (5.5, 20));
comment on column public.ventes."tva" is 'TVA de la vente du bien (20 ou 5,5) ; `prix` est le prix TTC à cette TVA, base des honoraires.';

-- 3. La vente créée depuis la fiche reprend la TVA choisie
do $$
declare def text; neuf text;
begin
  select pg_get_functiondef('public.vente_depuis_fiche'::regproc) into def;
  neuf := replace(def,
    'honoraires, taux, "tauxHonoraires", contact_id)',
    'honoraires, taux, "tauxHonoraires", contact_id, "tva")');
  neuf := replace(neuf,
    'coalesce(v_taux,0), v_taux_hono, p_contact);',
    'coalesce(v_taux,0), v_taux_hono, p_contact,
      case when replace(trim(coalesce(vl->>''tva'','''')), '','', ''.'') = ''5.5'' then 5.5 else 20 end);');
  if neuf = def or position('"tva")' in neuf) = 0 or position('then 5.5 else 20 end' in neuf) = 0 then
    raise exception 'vente_depuis_fiche : remplacement incomplet';
  end if;
  execute neuf;
end $$;
