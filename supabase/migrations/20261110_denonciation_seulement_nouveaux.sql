-- Demande d'Alex du 10/11/2026 (« fais uniquement pour les futures demandes ») : sur chaque compte, le
-- robot ne dénonce que les clients reçus après le branchement du compte (denonciation_comptes.valide_le),
-- pas ceux déjà dans le CRM au moment du branchement.

create or replace function public.robot_denonciations_a_faire_plateformes(p_cle text, p_limite integer default 40)
returns table (contact_id uuid, prenom text, nom_famille text, nom text, email text, telephone text, plateforme text,
               compte text, programmes text[], ville text, cp text, cp_obligatoire boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
  with leads as (
    select distinct c.id, public.ville_norm(v) as vn, c.recu_le
    from public.contacts c, unnest(string_to_array(coalesce(c.lieu, ''), ',')) v
    where c.recu_le >= timestamptz '2026-11-09 00:00:00+01'
      and (c.recu_le >= now() - interval '3 days' or c.denonciation_relance_le >= now() - interval '3 days')
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
                      and d.statut in ('envoyee', 'acceptee', 'refusee', 'deja_connu', 'a_faire_main'))
    and (select count(*) from public.denonciations d
         where d.contact_id = x.id and d.compte = x.compte
           and (not x.par_programme or d.programme = x.cle) and d.statut = 'echec'
           and d.fait_le > coalesce(c.denonciation_relance_le, '-infinity'::timestamptz)) < 2
    and (x.plateforme not in ('iselection', 'station9', 'unlatch', 'cogedim', 'accueil')
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(i.prenom) is not null)
    and (x.plateforme <> 'station9'
         or public.denonciation_revenu(c.budget_min, c.budget_max, c.prix_annonce) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;
