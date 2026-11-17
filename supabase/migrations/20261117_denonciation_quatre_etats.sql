-- Dénonciations en 4 états (demande d'Alex du 17/11/2026 : « que les équipes voient vraiment ce qui fonctionne et
-- aillent dénoncer là où on a des doutes ») :
--   vert   = envoyé et retrouvé chez le promoteur (preuve_niveau 'liste')
--   bleu   = envoyé, le site l'a seulement confirmé par un message (preuve_niveau 'message') : à vérifier
--   rouge  = refusé ou déjà connu du promoteur
--   orange = à dénoncer à la main (aucune dénonciation, deux échecs du robot, paternité terminée…)
-- Sauvegarde faite avant : public.denonciations_backup_20261117 (907 lignes).
alter table public.denonciations_backup_20261117 enable row level security;

alter table public.denonciations
  add column if not exists preuve_niveau text check (preuve_niveau in ('liste', 'message')),
  add column if not exists portee text check (portee in ('programme', 'client')),
  add column if not exists paternite_fin date;
comment on column public.denonciations.preuve_niveau is 'liste = client retrouvé chez le promoteur après l''envoi ; message = seulement le message de confirmation du site';
comment on column public.denonciations.portee is 'client = la dénonciation couvre tous les programmes du promoteur (compte sans par_programme)';
comment on column public.denonciations.paternite_fin is 'Fin de la paternité accordée par le promoteur, quand on connaît sa durée (denonciation_comptes.paternite_jours)';

alter table public.denonciation_comptes add column if not exists paternite_jours integer;
comment on column public.denonciation_comptes.paternite_jours is 'Durée de la paternité accordée par le promoteur (jours), si connue';
update public.denonciation_comptes set paternite_jours = 30 where compte in ('cogedim', 'ogic', 'mydbi');
update public.denonciation_comptes set paternite_jours = 60 where compte = 'ymmea';

-- Niveau de preuve déduit du détail noté par le robot (« retrouvé dans la liste », fiche Immo-Lead enregistrée),
-- sauf si le robot le donne lui-même.
create or replace function public.denonciation_preuve_niveau(p_statut text, p_detail text)
returns text language sql immutable as $$
  select case
    when p_statut not in ('envoyee', 'acceptee') then null
    when p_detail ~* '(retrouv|Enregistrer le contact)' then 'liste'
    else 'message' end
$$;

create or replace function public.denonciations_completer()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_par boolean; v_jours integer;
begin
  select dc.par_programme, dc.paternite_jours into v_par, v_jours
  from public.denonciation_comptes dc where dc.compte = new.compte limit 1;
  if new.portee is null then
    new.portee := case when v_par is false then 'client' else 'programme' end;
  end if;
  if new.preuve_niveau is null then
    new.preuve_niveau := public.denonciation_preuve_niveau(new.statut, new.detail);
  end if;
  if new.paternite_fin is null and v_jours is not null and new.statut in ('envoyee', 'acceptee') then
    new.paternite_fin := (coalesce(new.fait_le, now()) at time zone 'Europe/Paris')::date + v_jours;
  end if;
  return new;
end $$;
drop trigger if exists denonciations_completer on public.denonciations;
create trigger denonciations_completer before insert on public.denonciations
  for each row execute function public.denonciations_completer();

-- Lignes existantes
update public.denonciations d set
  portee = case when dc.par_programme is false then 'client' else 'programme' end,
  preuve_niveau = public.denonciation_preuve_niveau(d.statut, d.detail),
  paternite_fin = case when dc.paternite_jours is not null and d.statut in ('envoyee', 'acceptee')
                       then (d.fait_le at time zone 'Europe/Paris')::date + dc.paternite_jours end
from public.denonciation_comptes dc where dc.compte = d.compte;
update public.denonciations d set preuve_niveau = public.denonciation_preuve_niveau(d.statut, d.detail)
where d.preuve_niveau is null and d.statut in ('envoyee', 'acceptee');

-- Le robot peut donner le niveau de preuve lui-même (p_ligne->>'preuve_niveau').
create or replace function public.robot_denonciation_noter(p_cle text, p_ligne jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare v_id bigint; v_nom text; v_src text;
begin
  if p_cle is null or length(p_cle) < 32 or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  select i.prenom || ' ' || i.nom, i.source into v_nom, v_src
  from public.contacts c, public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
  where c.id = (p_ligne->>'contact_id')::uuid;
  insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail, preuve,
                                    ref_externe, civilite, nom_utilise, nom_source, preuve_niveau)
  values ((p_ligne->>'contact_id')::uuid, p_ligne->>'plateforme', p_ligne->>'compte', p_ligne->>'promoteur',
          p_ligne->>'programme', p_ligne->>'ville', p_ligne->>'statut', left(p_ligne->>'detail', 4000), p_ligne->>'preuve',
          p_ligne->>'ref_externe', p_ligne->>'civilite', v_nom, v_src, nullif(p_ligne->>'preuve_niveau', ''))
  returning denonciations.id into v_id;
  return v_id;
end $function$;
