-- Dénonciations Link-app (Primavefa, NACA, Infineo, GBI) : le robot sait maintenant faire la deuxième étape,
-- dénoncer le contact sur chaque programme (contrôle réel réussi chez Primavefa le 25/11/2026, « Valide » d'Alex ;
-- essais sans envoi réussis chez NACA, Infineo, GBI).
--   1. Les comptes Link-app passent « un envoi par programme » et ne sont plus « contact seul » : une ligne
--      'envoyee' retrouvée dans « Dénonciations » redevient verte.
--   2. La file ne compte plus une ligne « contact créé » comme faite.
--   3. Rattrapage : un client reçu depuis le 20/11/2026 et sorti de la fenêtre de 3 jours revient dans la file,
--      mais seulement pour les programmes où il a une ligne « contact créé » (pas pour les autres promoteurs).
--      Les demandes du 9 au 19/11 ne sont pas rattrapées (décision d'Alex du 25/11/2026).
-- NON APPLIQUÉ au 25/11/2026 : attend le « pousse » d'Alex pour glr-pige (lance de vraies dénonciations)
-- et le « pousse » de glr-pige (sans le nouveau robot, la file se remplirait pour rien).

create table if not exists public.fonctions_backup_20261125 as
  select p.proname::text as nom, pg_get_functiondef(p.oid) as definition, now() as sauvegarde_le
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'robot_denonciations_a_faire_plateformes';
alter table public.fonctions_backup_20261125 enable row level security;

update public.denonciation_comptes set par_programme = true, contact_seul = false where plateforme = 'linkapp';

-- La fiche de test dénoncée pour de vrai le 25/11/2026 (Linea Rosa) : la ligne est née « contact créé ».
update public.denonciations set preuve_niveau = 'liste'
 where contact_id = 'bf7df9cb-4def-4ab0-b4fb-bf05cf97bad9' and compte = 'linkapp_primavefa' and programme = 'Linea Rosa'
   and statut = 'envoyee' and preuve_niveau = 'contact' and detail like '%dénoncé sur le programme%';

CREATE OR REPLACE FUNCTION public.robot_denonciations_a_faire_plateformes(p_cle text, p_limite integer DEFAULT 40)
 RETURNS TABLE(contact_id uuid, prenom text, nom_famille text, nom text, email text, telephone text, plateforme text, compte text, programmes text[], ville text, cp text, cp_obligatoire boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
  with leads as (
    -- frais = dans la fenêtre de 3 jours (ou relancé) ; sinon le lead n'est là que pour le rattrapage de ses
    -- lignes « contact créé » (Link-app, 25/11/2026)
    select distinct c.id, public.ville_norm(v) as vn, c.recu_le,
           (c.recu_le >= now() - interval '3 days' or coalesce(c.denonciation_relance_le >= now() - interval '3 days', false)) as frais
    from public.contacts c, unnest(string_to_array(coalesce(c.lieu, ''), ',')) v
    where c.recu_le >= timestamptz '2026-11-09 00:00:00+01'
      and (c.recu_le >= now() - interval '3 days' or c.denonciation_relance_le >= now() - interval '3 days'
           -- rattrapage limité aux demandes reçues depuis le 20/11/2026 (décision d'Alex du 25/11/2026 :
           -- « fais que celle du 20 au 25 et vide la file d'attente pour le reste ») ; les plus anciennes
           -- restent en orange « Contact créé · à dénoncer », à faire à la main
           or (c.recu_le >= timestamptz '2026-11-20 00:00:00+01'
               and exists (select 1 from public.denonciations d0 where d0.contact_id = c.id
                           and d0.statut = 'envoyee' and d0.preuve_niveau = 'contact')))
      and exists (select 1 from public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email))
      and coalesce(c.statut, '') <> 'Stop'
      and coalesce(c.source, '') <> 'Ancien lead RAM'
      and coalesce(c.email, '') <> '' and coalesce(c.telephone, '') <> ''
  ),
  progs as (
    select distinct split_part(p.source, '_', 1) as plateforme, p.source as compte, p.nom, p.ville, p.cp,
           public.ville_norm(p.ville) as vn
    from public.pige_programmes p
    where p.source not like 'immolead\_%' and coalesce(p.nb_libres, 0) > 0
  ),
  cible as (
    select l.id, min(l.recu_le) as recu_le, g.plateforme, g.compte, dc.par_programme, dc.cp_obligatoire,
           case when dc.par_programme then g.nom else '' end as cle,
           array_agg(distinct g.nom order by g.nom) as programmes, min(g.ville) as ville, min(g.cp) as cp
    from leads l
    join progs g on g.vn = l.vn and g.vn <> ''
    join public.denonciation_comptes dc on dc.plateforme = g.plateforme and dc.compte = g.compte and dc.actif
      and l.recu_le >= coalesce(dc.valide_le, '-infinity'::timestamptz)
    where l.frais
       or exists (select 1 from public.denonciations d1 where d1.contact_id = l.id and d1.compte = g.compte
                  and d1.programme = g.nom and d1.statut = 'envoyee' and d1.preuve_niveau = 'contact')
    group by l.id, g.plateforme, g.compte, dc.par_programme, dc.cp_obligatoire, case when dc.par_programme then g.nom else '' end
  )
  select x.id, i.prenom, i.nom, i.prenom || ' ' || i.nom, c.email, c.telephone,
         x.plateforme, x.compte, x.programmes, x.ville, x.cp, x.cp_obligatoire
  from cible x join public.contacts c on c.id = x.id
  cross join lateral public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
  where not exists (select 1 from public.denonciations d
                    join public.contacts c2 on c2.id = d.contact_id
                    where (d.contact_id = x.id or lower(c2.email) = lower(c.email))
                      and d.compte = x.compte
                      and (not x.par_programme or d.programme = x.cle)
                      and d.statut in ('envoyee', 'acceptee', 'refusee', 'deja_connu', 'a_faire_main')
                      -- « contact créé » n'est pas une dénonciation (Link-app, 25/11/2026)
                      and coalesce(d.preuve_niveau, '') <> 'contact')
    and (select count(*) from public.denonciations d
         where d.contact_id = x.id and d.compte = x.compte
           and (not x.par_programme or d.programme = x.cle) and d.statut = 'echec'
           and d.fait_le > coalesce(c.denonciation_relance_le, '-infinity'::timestamptz)) < 2
    and (x.plateforme not in ('iselection', 'station9', 'unlatch', 'cogedim', 'accueil', 'pichet', 'lppromotion', 'saintagne', 'europeanhomes', 'duval', 'ogic', 'concilio', 'pirphi', 'nexity', 'greencity')
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(i.prenom) is not null)
    and (x.plateforme <> 'station9'
         or public.denonciation_revenu(c.budget_min, c.budget_max, c.prix_annonce) is not null)
    and (x.plateforme <> 'ymmea'
         or (coalesce(nullif(c.budget_max, 0), nullif(c.budget_min, 0), nullif(c.prix_annonce, 0)) is not null
             and public.denonciation_typologie(c.typologie) is not null))
    and (x.plateforme <> 'odea' or public.denonciation_vendeur(c.vendeur) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$function$;
