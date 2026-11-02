-- Taux de commission au passage en Vendu (demande d'Alex du 02/11/2026)
-- Le vendeur saisit le taux dans la fenêtre « Vendu » : il arrive dans
-- contacts.vente_lot.taux_honoraires. La vente créée automatiquement reprend ce
-- taux et calcule les honoraires (prix × taux), au lieu de partir de 0.
-- Sans taux (ancien CRM encore ouvert) : même comportement qu'avant.

-- 1. Sauvegarde de la fonction modifiée
create table if not exists public.fonctions_backup_20261102 as
select p.proname, pg_get_functiondef(p.oid) as definition, now() as sauve_le
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'vente_depuis_fiche';
alter table public.fonctions_backup_20261102 enable row level security;
revoke all on public.fonctions_backup_20261102 from anon, authenticated;
grant all on public.fonctions_backup_20261102 to service_role;

-- 2. La vente reprend le taux et calcule les honoraires
CREATE OR REPLACE FUNCTION public.vente_depuis_fiche(p_contact uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c record; vl jsonb; v_id text; v_vendeur_id text; v_taux numeric; v_prix numeric;
  v_titre text; v_programme text; v_lot text; v_prix_txt text;
  v_taux_hono numeric := 0; v_hono numeric := 0; v_taux_txt text;
begin
  select * into c from public.contacts where id = p_contact;
  if c is null or c.statut is distinct from 'Vendu' then return null; end if;
  vl := coalesce(c.vente_lot, '{}'::jsonb);
  if jsonb_typeof(vl) <> 'object' then vl := '{}'::jsonb; end if;
  if exists (select 1 from public.ventes v where v.contact_id = p_contact and v.deleted_at is null) then return null; end if;

  select p.vendeur_id into v_vendeur_id from public.profils p
   where public.normalise_vendeur(p.prenom) = public.normalise_vendeur(c.vendeur) limit 1;
  if v_vendeur_id is null then
    select v->>'id' into v_vendeur_id
      from public.dashboard_data d, jsonb_array_elements(coalesce(d.vendeurs,'[]'::jsonb)) v
     where d.id = 'main' and public.normalise_vendeur(v->>'prenom') = public.normalise_vendeur(c.vendeur) limit 1;
  end if;
  select nullif(v->>'tauxDefaut','')::numeric into v_taux
    from public.dashboard_data d, jsonb_array_elements(coalesce(d.vendeurs,'[]'::jsonb)) v
   where d.id = 'main' and v->>'id' = v_vendeur_id limit 1;

  v_prix_txt := regexp_replace(replace(coalesce(vl->>'prix',''), ',', '.'), '[^0-9.]', '', 'g');
  if v_prix_txt ~ '^[0-9]+(\.[0-9]+)?$' then v_prix := v_prix_txt::numeric; end if;

  v_taux_txt := replace(trim(coalesce(vl->>'taux_honoraires','')), ',', '.');
  if v_taux_txt ~ '^[0-9]+(\.[0-9]+)?$' then v_taux_hono := v_taux_txt::numeric; end if;
  if v_prix is not null then v_hono := round(v_prix * v_taux_hono / 100, 2); end if;

  v_titre := trim(coalesce(vl->>'titre',''));
  v_programme := nullif(trim(coalesce(vl->>'programme','')),'');
  v_lot := nullif(trim(coalesce(vl->>'lot','')),'');
  if v_programme is null then
    if v_titre ~ '\s[—–-]\s' then
      v_programme := trim(split_part(regexp_replace(v_titre, '\s[—–-]\s', '|', 'g'), '|', 1));
      v_lot := coalesce(v_lot, nullif(trim(regexp_replace(substr(regexp_replace(v_titre, '\s[—–-]\s', '|', 'g'), length(v_programme) + 2), '^(Lot|lot)\s*', '')), ''));
    else
      v_programme := nullif(v_titre,'');
    end if;
  end if;
  if v_programme is null then v_programme := 'Programme à préciser'; end if;

  v_id := 'auto_' || substr(replace(gen_random_uuid()::text,'-',''), 1, 18);
  insert into public.ventes (id, client, "clientNom", "clientPrenom", "clientEmail", "clientTelephone",
      "coNom", "coPrenom", programme, promoteur, lot, ville, "vendeurId", statut, notes, date, prix,
      honoraires, taux, "tauxHonoraires", contact_id)
  values (v_id, trim(coalesce(c.prenom,'') || ' ' || coalesce(c.nom_famille,'')), coalesce(c.nom_famille,''),
      coalesce(c.prenom,''), coalesce(c.email,''), coalesce(c.telephone,''),
      coalesce(c.conjoint->>'nom',''), coalesce(c.conjoint->>'prenom',''),
      v_programme, coalesce(nullif(trim(vl->>'promoteur'),''),''), coalesce(v_lot,''),
      coalesce(nullif(trim(vl->>'ville'),''),''), v_vendeur_id, 'reservation',
      case when v_hono > 0 then 'Créée automatiquement depuis la fiche client (passage en Vendu).'
           else 'Créée automatiquement depuis la fiche client (passage en Vendu). Honoraires à compléter.' end,
      (now() at time zone 'Europe/Paris')::date, v_prix, v_hono, coalesce(v_taux,0), v_taux_hono, p_contact);
  return v_id;
end; $function$;
