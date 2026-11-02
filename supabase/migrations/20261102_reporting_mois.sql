-- Rubrique Reporting (demande d'Alex du 02/11/2026) : tous les chiffres du mois par
-- commercial, en une lecture, réservés aux gérants. La page les recalcule à chaque ouverture.
-- Parcours : leads entrés depuis le début du mois et depuis au moins 7 jours.
-- Joint = preuve (sélection, RDV, statut Sélections et au-delà), jamais Suivi ni En veille.
-- Essais : jours d'appel différents. Clients vus : RDV du mois précédent et du mois.
CREATE OR REPLACE FUNCTION public.reporting_mois(p_mois date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d timestamptz := date_trunc('month', p_mois::timestamp) at time zone 'Europe/Paris';
  f timestamptz := (date_trunc('month', p_mois::timestamp) + interval '1 month') at time zone 'Europe/Paris';
  c timestamptz;
  res jsonb;
begin
  if not public.est_gerant() then raise exception 'Réservé aux gérants'; end if;
  c := least(f, now() - interval '7 days');

  with noms as (
    select p.prenom v, p.vendeur_id from public.profils p where p.role = 'commercial' and p.prenom is not null
  ),
  h as (
    select k.id, e.value->>'vendeur' de,
           coalesce(lead(e.value->>'vendeur') over (partition by k.id order by e.ordinality), k.vendeur) vers,
           (e.value->>'au')::timestamptz au, coalesce(e.value->>'motif','') motif
      from public.contacts k, jsonb_array_elements(coalesce(k.vendeur_historique,'[]'::jsonb)) with ordinality e
  ),
  ent as (
    select k.id, e->>'vendeur' v, (e->>'le')::timestamptz t0, 'direct' canal from public.contacts k, jsonb_array_elements(k.recu_par) e
    union all select id, vers, au, 'transfert' from h where motif like 'réattribution%'
    union all select contact_id, vendeur, pris_le, 'pool' from public.pool_prises
  ),
  e1 as (
    select distinct on (e.id, e.v) e.id, e.v, e.t0, e.canal
      from ent e join noms n on n.v = e.v
     where e.t0 >= d and e.t0 < c
     order by e.id, e.v, e.t0
  ),
  ja as (
    select e.id, e.v,
      bool_or(j.action = 'statut' and j.apres in ('Sélections','Retour documentation','Finaliser la vente','Vendu')) joint_st,
      bool_or(j.action = 'statut' and j.apres in ('Perdu','Non qualifié')) clos,
      min(j.quand) prem, max(j.quand) dern
    from e1 e join public.journal_audit j on j.ligne_id = e.id and j.acteur = e.v and j.cible = 'contacts'
      and j.quand >= e.t0 and j.action in ('statut','activite','modification')
    group by 1, 2
  ),
  ap as (
    select e.id, e.v, count(*) nb, array_agg((a->>'le')::timestamptz order by (a->>'le')::timestamptz) le,
      count(distinct ((a->>'le')::timestamptz at time zone 'Europe/Paris')::date) jours
    from e1 e join public.contacts k on k.id = e.id, jsonb_array_elements(coalesce(k.appels,'[]'::jsonb)) a
    where a->>'vendeur' = e.v and (a->>'le')::timestamptz >= e.t0
    group by 1, 2
  ),
  x as (
    select e.*, k.statut, k.rappel_le, k.vendeur actuel, coalesce(ap.jours, 0) jours, ap.le ap_le,
      coalesce(ja.clos, false) clos0,
      exists (select 1 from public.selections s where s.contact_id = e.id and s.vendeur = e.v and s.created_at >= e.t0) a_sel,
      exists (select 1 from public.creneaux q where q.contact_id = e.id and q.vendeur = e.v and q.statut = 'confirme' and q.origine is null and q.debut >= e.t0) a_rdv,
      coalesce(ja.joint_st, false) joint_st,
      least(ja.prem, ap.le[1]) t1, greatest(ja.dern, ap.le[array_length(ap.le, 1)]) tz,
      exists (select 1 from public.ventes w, noms n where n.v = e.v and w.contact_id = e.id and w.deleted_at is null and w."vendeurId" = n.vendeur_id) vendu
    from e1 e join public.contacts k on k.id = e.id
    left join ja on ja.id = e.id and ja.v = e.v
    left join ap on ap.id = e.id and ap.v = e.v
  ),
  y as (select *, (joint_st or a_sel or a_rdv) j from x),
  coh as (
    select v, jsonb_build_object(
      'ent', count(*),
      'joints', count(*) filter (where j),
      'sel', count(*) filter (where a_sel),
      'rdv', count(*) filter (where a_rdv),
      'av', count(*) filter (where statut in ('Retour documentation','Finaliser la vente') and actuel = v),
      've', count(*) filter (where vendu),
      'cl', count(*) filter (where not j and clos0),
      'zero', count(*) filter (where not j and not clos0 and jours = 0),
      'j1', count(*) filter (where not j and not clos0 and jours = 1),
      'j2', count(*) filter (where not j and not clos0 and jours = 2),
      'j3', count(*) filter (where not j and not clos0 and jours >= 3),
      'oub', count(*) filter (where not j and not clos0 and coalesce(tz, t0) < now() - interval '7 days'
                                and statut <> 'En veille' and coalesce(rappel_le, '2000-01-01') < current_date and actuel = v),
      'touche24', count(*) filter (where t1 <= t0 + interval '24 hours'),
      'dir_n', count(*) filter (where canal = 'direct'), 'dir_j', count(*) filter (where canal = 'direct' and j),
      'tr_n', count(*) filter (where canal = 'transfert'), 'tr_j', count(*) filter (where canal = 'transfert' and j),
      'pool_n', count(*) filter (where canal = 'pool'), 'pool_j', count(*) filter (where canal = 'pool' and j),
      'delai2', round((percentile_cont(0.5) within group (order by extract(epoch from ap_le[2] - ap_le[1]) / 86400)
                 filter (where array_length(ap_le, 1) >= 2 and ap_le[2] - ap_le[1] > interval '6 hours'))::numeric, 1)
    ) o from y group by v
  ),
  fl as (select * from h where au >= d and au < f),
  rdvc as (
    select q.contact_id, q.vendeur v, max(q.debut) dernier from public.creneaux q join noms n on n.v = q.vendeur
     where q.statut = 'confirme' and q.origine is null and q.contact_id is not null
       and q.debut >= d - interval '1 month' and q.debut < c
     group by 1, 2
  ),
  vus as (
    select r.v, count(*) vus,
      count(*) filter (where exists (select 1 from public.journal_audit j where j.ligne_id = k.id and j.acteur = r.v and j.cible = 'contacts'
                          and j.action in ('statut','activite') and j.quand > r.dernier and j.quand <= r.dernier + interval '7 days')
                        or exists (select 1 from public.selections s where s.contact_id = k.id and s.created_at > r.dernier and s.created_at <= r.dernier + interval '7 days')) suite7,
      count(*) filter (where k.statut not in ('En veille','Perdu','Non qualifié','Stop','Vendu')
                         and not exists (select 1 from public.ventes w where w.contact_id = k.id and w.deleted_at is null)
                         and not (coalesce(k.derniere_action_le, k.recu_le) >= now() - interval '14 days' or k.rappel_le >= current_date)) sans_suite,
      count(*) filter (where k.statut = 'En veille') en_veille
    from rdvc r join public.contacts k on k.id = r.contact_id and k.vendeur = r.v group by 1
  ),
  cal as (
    select j.acteur v, jsonb_object_agg(j.jour, j.n) o, count(*) jours_actifs, sum(j.n) actions
    from (select a.acteur, ((a.quand at time zone 'Europe/Paris')::date)::text jour, count(*) n
            from public.journal_audit a join noms n on n.v = a.acteur
           where a.cible = 'contacts' and a.action in ('statut','activite') and a.quand >= d and a.quand < f group by 1, 2) j
    group by 1
  )
  select jsonb_build_object('debut', d, 'fin', f, 'coupure', c, 'calcule_le', now(), 'vendeurs',
    coalesce(jsonb_agg(jsonb_build_object(
      'v', n.v,
      'recus', (select count(distinct k.id) from public.contacts k, jsonb_array_elements(k.recu_par) e where e->>'vendeur' = n.v and (e->>'le')::timestamptz >= d and (e->>'le')::timestamptz < f),
      'tr', (select count(*) from fl where vers = n.v and motif like 'réattribution%'),
      'trg', (select count(*) from fl where vers = n.v and motif like 'réattribution%' and de in (select prenom from public.profils where role = 'gerant')),
      'env', (select count(*) from fl where de = n.v and motif like 'réattribution%'),
      'ech', (select count(*) from fl where de = n.v and motif like 'paternité échue%'),
      'pool', (select count(*) from public.pool_prises p where p.vendeur = n.v and p.pris_le >= d and p.pris_le < f),
      'coh', coalesce(coh.o, '{}'::jsonb),
      'cal', coalesce(cal.o, '{}'::jsonb), 'jours_actifs', coalesce(cal.jours_actifs, 0), 'actions', coalesce(cal.actions, 0),
      'clients', (select count(distinct a.ligne_id) from public.journal_audit a where a.acteur = n.v and a.cible = 'contacts' and a.action in ('statut','activite') and a.quand >= d and a.quand < f),
      'ess', (select count(*) from public.contacts k, jsonb_array_elements(coalesce(k.appels,'[]'::jsonb)) a where a->>'vendeur' = n.v and (a->>'le')::timestamptz >= d and (a->>'le')::timestamptz < f),
      'app', (select count(distinct k.id) from public.contacts k, jsonb_array_elements(coalesce(k.appels,'[]'::jsonb)) a where a->>'vendeur' = n.v and (a->>'le')::timestamptz >= d and (a->>'le')::timestamptz < f),
      'selections', (select jsonb_build_object('env', count(*), 'clients', count(distinct s.contact_id), 'ouv', count(*) filter (where s.opened_at is not null),
                        'reac', count(*) filter (where s.avis is not null and s.avis not in ('{}'::jsonb, '[]'::jsonb, 'null'::jsonb)))
                       from public.selections s where s.vendeur = n.v and s.created_at >= d and s.created_at < f),
      'rdv_mois', (select count(*) from public.creneaux q where q.vendeur = n.v and q.statut = 'confirme' and q.origine is null and q.debut >= d and q.debut < f),
      'ventes', (select count(*) from public.ventes w where w."vendeurId" = n.vendeur_id and w.deleted_at is null and w.date >= (d at time zone 'Europe/Paris')::date and w.date < (f at time zone 'Europe/Paris')::date),
      'hono', (select coalesce(sum(w.honoraires - coalesce(w."offreGlr", 0)), 0) from public.ventes w where w."vendeurId" = n.vendeur_id and w.deleted_at is null and w.date >= (d at time zone 'Europe/Paris')::date and w.date < (f at time zone 'Europe/Paris')::date),
      'vus', coalesce(vus.vus, 0), 'suite7', coalesce(vus.suite7, 0), 'sans_suite', coalesce(vus.sans_suite, 0), 'vus_veille', coalesce(vus.en_veille, 0),
      'pf', (select jsonb_build_object(
          'actifs', count(*) filter (where k.statut in ('Nouveau','Suivi','Sélections','Retour documentation','Finaliser la vente','Sans réponse')),
          'retards', count(*) filter (where k.statut in ('Nouveau','Suivi','Sélections','Retour documentation','Finaliser la vente','Sans réponse') and k.rappel_le < current_date),
          'sr', count(*) filter (where k.statut = 'Sans réponse'),
          'sr0', count(*) filter (where k.statut = 'Sans réponse' and jsonb_array_length(coalesce(k.appels,'[]'::jsonb)) = 0),
          'fin', count(*) filter (where k.statut = 'Finaliser la vente'),
          'fin7', count(*) filter (where k.statut = 'Finaliser la vente' and k.derniere_action_le < now() - interval '7 days'),
          'rd', count(*) filter (where k.statut = 'Retour documentation'),
          'rd7', count(*) filter (where k.statut = 'Retour documentation' and k.derniere_action_le < now() - interval '7 days'),
          'pat7', count(*) filter (where k.statut in ('Nouveau','Suivi','Sélections','Retour documentation','Finaliser la vente','Sans réponse') and k.paternite_jusqu_au >= now() and k.paternite_jusqu_au < now() + interval '7 days'),
          'veille', count(*) filter (where k.statut = 'En veille'))
        from public.contacts k where k.vendeur = n.v)
    ) order by n.v), '[]'::jsonb)) into res
  from noms n
  left join coh on coh.v = n.v
  left join vus on vus.v = n.v
  left join cal on cal.v = n.v;
  return res;
end; $function$;

revoke all on function public.reporting_mois(date) from public, anon;
grant execute on function public.reporting_mois(date) to authenticated, service_role;
