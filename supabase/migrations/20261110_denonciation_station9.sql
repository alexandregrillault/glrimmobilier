-- Dénonciation Station 9 (repérage avec Alex dans son Chrome, 10/11/2026) :
-- « Mes clients » → « Créer un nouveau client » (civilité, nom, prénom, e-mail, téléphone, code postal,
-- ville, revenu net mensuel, tous obligatoires), puis « Dénoncer » sur la ligne du client : promoteur
-- (Quartus, Eiffage Immobilier, Spirit, Cybelim, Pierreval, Promethee, Accueil Immobilier) et programme.
-- Revenu net mensuel : décision d'Alex « d'après le budget » = budget de la fiche (max, sinon min),
-- sinon prix de l'annonce, divisé par 100, arrondi à la centaine (300 000 € → 3 000 €/mois).
-- Ville et code postal : la ville cherchée (comme Bouygues). Sans budget ni prix : pas de Station 9,
-- le carré rouge de la fiche demande le budget.

create or replace function public.denonciation_revenu(p_budget_min bigint, p_budget_max bigint, p_prix numeric)
returns int language sql immutable set search_path = public as $$
  select case when coalesce(p_budget_max, p_budget_min, p_prix) >= 10000
              then (round(coalesce(p_budget_max, p_budget_min, p_prix) / 100 / 100) * 100)::int end
$$;
grant execute on function public.denonciation_revenu(bigint, bigint, numeric) to authenticated, service_role;

create or replace function public.robot_contact_revenu(p_cle text, p_id uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select public.denonciation_revenu(c.budget_min, c.budget_max, c.prix_annonce) from public.contacts c where c.id = p_id);
end
$$;
revoke all on function public.robot_contact_revenu(text, uuid) from public;
grant execute on function public.robot_contact_revenu(text, uuid) to anon, authenticated, service_role;

-- Promoteur d'un programme de la pige (Station 9 demande le promoteur avant le programme).
create or replace function public.robot_programme_promoteur(p_cle text, p_source text, p_nom text)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select p.promoteur from public.pige_programmes p where p.source = p_source and p.nom = p_nom limit 1);
end
$$;
revoke all on function public.robot_programme_promoteur(text, text, text) from public;
grant execute on function public.robot_programme_promoteur(text, text, text) to anon, authenticated, service_role;

-- Compte Station 9 : créé inactif, activé après l'essai et le « valide » d'Alex.
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note) values
  ('station9', 'station9', true, true, false, null,
   'Repéré avec Alex le 10/11/2026 ; revenu net mensuel d''après le budget (décision d''Alex)')
on conflict (plateforme, compte) do nothing;

-- Branchement (10/11/2026, « valide » d'Alex) : premier envoi réel réussi (Aziz, Quartus, Les Jardins
-- d'Althéa, « Votre dénonciation a bien été enregistrée », retrouvé dans « Dénonciations »).
-- Station 9 exige civilité et revenu : sans l'un ou l'autre, pas de Station 9, et le carré rouge de la
-- fiche demande ce qui manque (« civilite », « budget »).

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
    and (x.plateforme not in ('iselection', 'station9')
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(i.prenom) is not null)
    and (x.plateforme <> 'station9'
         or public.denonciation_revenu(c.budget_min, c.budget_max, c.prix_annonce) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;

create or replace function public.denonciation_manques(p_contact uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.contacts;
  manque text[] := '{}';
  n int;
  n_civ int;
  n_s9 int;
  i record;
  ecart jsonb;
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
  select * into i from public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email);
  select count(*), count(*) filter (where plateforme in ('iselection', 'station9')),
         count(*) filter (where plateforme = 'station9')
  into n, n_civ, n_s9
  from public.denonciation_cibles(p_contact);
  if n > 0 and i.prenom is null then
    manque := manque || 'nom';
  end if;
  if n_civ > 0 and coalesce(c.civilite, '') not in ('Monsieur', 'Madame')
     and public.civilite_du_prenom(i.prenom) is null then
    manque := manque || 'civilite';
  end if;
  if n_s9 > 0 and public.denonciation_revenu(c.budget_min, c.budget_max, c.prix_annonce) is null then
    manque := manque || 'budget';
  end if;
  if i.source = 'fiche' then
    select jsonb_build_object('nom', min(d.nom_utilise), 'promoteurs', jsonb_agg(distinct coalesce(d.promoteur, d.compte)))
    into ecart
    from public.denonciations d
    where d.contact_id = p_contact and d.nom_source = 'email'
      and d.statut in ('envoyee', 'acceptee')
      and public.prenom_norm(d.nom_utilise) <> public.prenom_norm(i.prenom || ' ' || i.nom)
    having count(*) > 0;
  end if;
  return jsonb_build_object('manque', to_jsonb(manque), 'programmes', n,
    'identite', case when i.prenom is null then null
                     else jsonb_build_object('prenom', i.prenom, 'nom', i.nom, 'source', i.source) end,
    'ecart_nom', ecart);
end
$$;

update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'station9' and compte = 'station9';
