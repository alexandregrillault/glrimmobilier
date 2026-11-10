-- Dénonciation : fiche complète d'abord (décision d'Alex du 10/11/2026).
-- Sans prénom ET nom de famille distincts (« Morgane Morgane »), aucune dénonciation ne part,
-- sur aucune plateforme ; sans civilité (ni confirmée, ni déduite du prénom), pas d'iSelection.
-- La fiche montre un carré rouge au vendeur ; il complète, clique « C'est fait » : la base note
-- la relance (contacts.denonciation_relance_le), relance le robot, et la fenêtre de 3 jours repart
-- de cette relance (les échecs d'avant ne comptent plus).

alter table public.contacts add column if not exists denonciation_relance_le timestamptz;

-- Prénom et nom de famille connus et distincts, découpés comme le robot (client_de).
create or replace function public.denonciation_nom_complet(p_prenom text, p_nom_famille text, p_nom text)
returns boolean language plpgsql immutable set search_path = public as $$
declare
  pr text := trim(coalesce(p_prenom, ''));
  nf text := trim(coalesce(p_nom_famille, ''));
  mots text[];
  n int;
begin
  if nf = '' then
    mots := regexp_split_to_array(trim(coalesce(p_nom, '')), '\s+');
    n := coalesce(array_length(mots, 1), 0);
    if n > 1 then
      nf := mots[n];
      if pr = '' then pr := array_to_string(mots[1:n - 1], ' '); end if;
    else
      nf := trim(coalesce(p_nom, ''));
    end if;
  end if;
  return pr <> '' and nf <> '' and lower(pr) <> lower(nf);
end
$$;
grant execute on function public.denonciation_nom_complet(text, text, text) to authenticated, service_role;

-- Programmes encore à dénoncer pour un lead (comptes actifs, villes de la fiche), sans regarder
-- la fenêtre de temps ni la fiche : sert au carré rouge du CRM.
create or replace function public.denonciation_cibles(p_contact uuid)
returns table (plateforme text, compte text, programme text)
language sql stable security definer set search_path = public as $$
  with c as (select * from public.contacts where id = p_contact),
  villes as (select distinct public.ville_norm(v) vn from c, unnest(string_to_array(coalesce(c.lieu, ''), ',')) v),
  progs as (
    select distinct case when p.source like 'immolead\_%' then 'immolead' else split_part(p.source, '_', 1) end as plateforme,
           case when p.source like 'immolead\_%' then substr(p.source, 10) else p.source end as compte, p.nom
    from public.pige_programmes p join villes on public.ville_norm(p.ville) = villes.vn and villes.vn <> ''
    where coalesce(p.nb_libres, 0) > 0
  )
  select g.plateforme, g.compte, g.nom
  from progs g
  join public.denonciation_comptes dc on dc.plateforme = g.plateforme and dc.compte = g.compte and dc.actif
  where not exists (select 1 from public.denonciations d, c
                    where d.contact_id = c.id and d.compte = g.compte
                      and (d.programme = g.nom or (not dc.par_programme and g.plateforme <> 'immolead'))
                      and d.statut in ('envoyee', 'acceptee', 'refusee', 'deja_connu', 'a_faire_main'))
$$;
revoke all on function public.denonciation_cibles(uuid) from public, anon, authenticated;

-- Ce qui manque sur la fiche pour dénoncer : {"manque": ["nom", "civilite"], "programmes": n}.
-- Vide si rien n'est à dénoncer. Lisible par qui peut lire la fiche.
create or replace function public.denonciation_manques(p_contact uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.contacts;
  manque text[] := '{}';
  n int;
  n_isel int;
begin
  select * into c from public.contacts x
  where x.id = p_contact
    and (public.est_gerant() or public.paternite_peut_travailler(x, public.mon_prenom())
         or public.activite_conservee(x, public.mon_prenom()));
  if c.id is null
     or c.recu_le < timestamptz '2026-11-09 00:00:00+01'
     or coalesce(c.statut, '') = 'Stop' or coalesce(c.source, '') = 'Ancien lead RAM'
     or coalesce(c.email, '') = '' or coalesce(c.telephone, '') = '' then
    return jsonb_build_object('manque', '[]'::jsonb, 'programmes', 0);
  end if;
  select count(*), count(*) filter (where plateforme = 'iselection') into n, n_isel
  from public.denonciation_cibles(p_contact);
  if n > 0 and not public.denonciation_nom_complet(c.prenom, c.nom_famille, c.nom) then
    manque := manque || 'nom';
  end if;
  if n_isel > 0 and coalesce(c.civilite, '') not in ('Monsieur', 'Madame')
     and public.civilite_du_prenom(c.prenom) is null then
    manque := manque || 'civilite';
  end if;
  return jsonb_build_object('manque', to_jsonb(manque), 'programmes', n);
end
$$;
revoke all on function public.denonciation_manques(uuid) from public, anon;
grant execute on function public.denonciation_manques(uuid) to authenticated;

-- « C'est fait » : si la fiche est complète, note la relance et lance le robot.
create or replace function public.denonciation_relancer(p_contact uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m jsonb := public.denonciation_manques(p_contact);
  lancement text;
begin
  if jsonb_array_length(m->'manque') > 0 then
    return m || jsonb_build_object('relance', false);
  end if;
  update public.contacts set denonciation_relance_le = now() where id = p_contact;
  begin
    lancement := public.robot_lancer_denonciations();
  exception when others then
    lancement := 'au prochain passage horaire';
  end;
  return m || jsonb_build_object('relance', true, 'lancement', lancement);
end
$$;
revoke all on function public.denonciation_relancer(uuid) from public, anon;
grant execute on function public.denonciation_relancer(uuid) to authenticated;

-- Les deux listes « à faire » du robot : fiche complète, fenêtre de 3 jours depuis la réception
-- ou depuis le « C'est fait » du vendeur, échecs comptés depuis la dernière relance.
create or replace function public.robot_denonciations_a_faire(p_cle text, p_limite int default 60)
returns table (contact_id uuid, nom_complet text, email text, telephone text, plateforme text, compte text,
               programme text, ville text, cp text, cp_obligatoire boolean)
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
      and public.denonciation_nom_complet(c.prenom, c.nom_famille, c.nom)
      and coalesce(c.statut, '') <> 'Stop'
      and coalesce(c.source, '') <> 'Ancien lead RAM'
      and coalesce(c.email, '') <> '' and coalesce(c.telephone, '') <> ''
  ),
  progs as (
    select distinct 'immolead'::text as plateforme, substr(p.source, 10) as compte, p.nom, p.ville, p.cp,
           public.ville_norm(p.ville) as vn
    from public.pige_programmes p
    where p.source like 'immolead\_%' and coalesce(p.nb_libres, 0) > 0
  ),
  cible as (
    select distinct on (l.id, g.compte, g.nom) l.id, l.recu_le, g.plateforme, g.compte, g.nom, g.ville, g.cp, dc.cp_obligatoire
    from leads l
    join progs g on g.vn = l.vn and g.vn <> ''
    join public.denonciation_comptes dc on dc.plateforme = g.plateforme and dc.compte = g.compte and dc.actif
  )
  select x.id, coalesce(nullif(trim(concat_ws(' ', c.prenom, c.nom_famille)), ''), c.nom), c.email, c.telephone,
         x.plateforme, x.compte, x.nom, x.ville, x.cp, x.cp_obligatoire
  from cible x join public.contacts c on c.id = x.id
  where not exists (select 1 from public.denonciations d
                    join public.contacts c2 on c2.id = d.contact_id
                    where (d.contact_id = x.id or lower(c2.email) = lower(c.email))
                      and d.compte = x.compte and d.programme = x.nom
                      and d.statut in ('envoyee', 'acceptee', 'refusee', 'deja_connu', 'a_faire_main'))
    and (select count(*) from public.denonciations d
         where d.contact_id = x.id and d.compte = x.compte and d.programme = x.nom and d.statut = 'echec'
           and d.fait_le > coalesce(c.denonciation_relance_le, '-infinity'::timestamptz)) < 2
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;

create or replace function public.robot_denonciations_a_faire_plateformes(p_cle text, p_limite int default 40)
returns table (contact_id uuid, prenom text, nom_famille text, nom text, email text, telephone text,
               plateforme text, compte text, programmes text[], ville text, cp text, cp_obligatoire boolean)
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
      and public.denonciation_nom_complet(c.prenom, c.nom_famille, c.nom)
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
    group by l.id, g.plateforme, g.compte, dc.par_programme, dc.cp_obligatoire, case when dc.par_programme then g.nom else '' end
  )
  select x.id, c.prenom, c.nom_famille, c.nom, c.email, c.telephone,
         x.plateforme, x.compte, x.programmes, x.ville, x.cp, x.cp_obligatoire
  from cible x join public.contacts c on c.id = x.id
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
    and (x.plateforme <> 'iselection'
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(c.prenom) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;
