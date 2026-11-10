-- Factures de commission : le gérant choisit ce qu'il paie (règle du 10/11/2026).
-- Dès la signature chez le notaire (ou vente payée), toute commission restante
-- peut être facturée, au montant choisi (par défaut tout le reste), même si le
-- promoteur n'a pas encore payé. Nouvelle fonction : facture_commerciale_emettre
-- reste en place et inchangée.
create or replace function public.facture_commerciale_emettre_libre(
  p_vente text, p_montant numeric, p_date date, p_taux_tva numeric, p_emetteur jsonb, p_payeur jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v record; hoje date := (now() at time zone 'Europe/Paris')::date;
  d date; an int; seq int; pref text; num text; mht numeric(12,2); tv numeric(12,2); derniere date;
  comm numeric(12,2); deja numeric(12,2); reste numeric(12,2); typ text; avance boolean; lib text; des text; avant jsonb;
  rec factures_commerciaux;
begin
  if not est_gerant() then raise exception 'Réservé aux gérants'; end if;
  select * into v from public.ventes where id = p_vente and deleted_at is null;
  if not found then raise exception 'Vente introuvable'; end if;
  if v."vendeurId" is null or v."vendeurId" = '' then raise exception 'Cette vente n''a pas de vendeur'; end if;
  if exists (select 1 from public.profils pr where pr.vendeur_id = v."vendeurId" and pr.role = 'gerant') then
    raise exception 'Les gérants sont rémunérés en salaire : pas de facture de commission';
  end if;
  if p_taux_tva is null or p_taux_tva not in (0, 20) then raise exception 'Taux de TVA invalide'; end if;
  if not (v.statut = 'facture-payee' or (v."dateSignatureNotaire" is not null and v."dateSignatureNotaire" <= hoje)) then
    raise exception 'Facture impossible : l''acte n''est pas encore signé chez le notaire';
  end if;
  comm := round(greatest(coalesce(v.honoraires, 0) - coalesce(v."offreGlr", 0), 0) * coalesce(v.taux, 0) / 100, 2);
  if comm <= 0 then raise exception 'Commission nulle : vérifie les honoraires et le taux de la vente'; end if;
  select coalesce(sum(f.ht), 0), coalesce(jsonb_agg(jsonb_build_object('numero', f.numero, 'ht', f.ht, 'type', f.type) order by f.created_at), '[]'::jsonb)
    into deja, avant from public.factures_commerciaux f where f.vente_id = v.id and f.statut <> 'annulee';
  reste := comm - deja;
  if reste <= 0.004 then raise exception 'La commission de cette vente est déjà entièrement facturée'; end if;
  mht := round(coalesce(p_montant, reste), 2);
  if mht <= 0 then raise exception 'Montant nul'; end if;
  if mht > reste + 0.004 then raise exception 'Montant supérieur au reste de la commission (% € HT)', reste; end if;

  avance := v.statut <> 'facture-payee';
  if mht >= reste - 0.004 then
    mht := reste;
    if deja > 0 then typ := 'solde'; lib := 'Solde de commission';
    else typ := 'commission'; lib := 'Commission sur vente'; end if;
  else
    typ := 'avance'; lib := 'Avance sur commission';
  end if;

  tv := round(mht * p_taux_tva / 100, 2);
  pref := regexp_replace(upper(translate(coalesce(p_emetteur->>'prenom', 'X'),
            'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaeeeeiioouuucAAAEEEEIIOOUUUC')), '[^A-Z0-9]', '', 'g');
  if pref = '' then pref := 'X'; end if;
  d := coalesce(p_date, hoje);
  perform pg_advisory_xact_lock(hashtext('fcom:' || v."vendeurId"));
  select max(f.date_facture) into derniere from public.factures_commerciaux f where f.vendeur_id = v."vendeurId";
  if derniere is not null and d < derniere then d := derniere; end if;
  an := extract(year from d)::int;
  select count(*) + 1 into seq from public.factures_commerciaux f
   where f.vendeur_id = v."vendeurId" and extract(year from f.date_facture) = an;
  num := pref || '-' || an || '-' || lpad(seq::text, 3, '0');
  des := lib || ' — ' || coalesce(v.programme, '') || case when coalesce(v.lot,'') <> '' then ' (lot ' || v.lot || ')' else '' end
         || case when coalesce(v.ville,'') <> '' then ' — ' || v.ville else '' end
         || case when coalesce(v.client,'') <> '' then ' — acquéreur : ' || v.client else '' end;
  insert into public.factures_commerciaux (numero, vendeur_id, vente_id, date_facture, avance, type, designation, ht, taux_tva, tva, ttc, emetteur, payeur, vente)
  values (num, v."vendeurId", v.id, d, avance, typ, des, mht, p_taux_tva, tv, mht + tv, coalesce(p_emetteur, '{}'::jsonb), coalesce(p_payeur, '{}'::jsonb),
          jsonb_build_object('programme', v.programme, 'lot', v.lot, 'ville', v.ville, 'client', v.client, 'promoteur', v.promoteur,
                             'prix', v.prix, 'honoraires', v.honoraires, 'offreGlr', v."offreGlr", 'taux', v.taux, 'dateSignatureNotaire', v."dateSignatureNotaire",
                             'commissionTotale', comm, 'dejaFacture', avant))
  returning * into rec;
  return to_jsonb(rec);
end $function$;

revoke all on function public.facture_commerciale_emettre_libre(text, numeric, date, numeric, jsonb, jsonb) from public, anon;
grant execute on function public.facture_commerciale_emettre_libre(text, numeric, date, numeric, jsonb, jsonb) to authenticated, service_role;
