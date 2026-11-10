-- Nom et prénom déduits de l'e-mail (décision d'Alex du 10/11/2026) : quand la fiche n'a qu'un mot
-- (« Morgane », « GIRARDIN »), on regarde l'e-mail : « morgane.lafagne@… », « jean-marc.girardin@… »,
-- « halimaabid@… ». Le mot de la fiche doit s'y retrouver tel quel ; l'autre morceau donne la partie
-- manquante. Prénom = le morceau qui est un prénom connu (table prenoms_civilite), sinon le premier.
-- Le robot dénonce sous ce nom ; le registre le garde (denonciations.nom_utilise, nom_source) ; la
-- fiche le met en avant pour que le vendeur le valide (« C'est bon ») ou le corrige. S'il le corrige
-- après coup, la fiche le prévient (« Dénoncé sous un autre nom ») jusqu'à « C'est corrigé ».
-- Rien n'est écrit sur la fiche sans le clic du vendeur.

create or replace function public.denonciation_identite(p_prenom text, p_nom_famille text, p_nom text, p_email text)
returns table (prenom text, nom text, source text)
language plpgsql stable set search_path = public as $$
declare
  pr text := trim(coalesce(p_prenom, ''));
  nf text := trim(coalesce(p_nom_famille, ''));
  mots text[];
  n int;
  w text;
  wn text;
  loc text;
  seg text[];
  autre text;
  wpos int;
  w_p boolean;
  a_p boolean;
  wf text;
  af text;
begin
  -- 1. La fiche suffit (découpage du robot, client_de)
  if public.denonciation_nom_complet(p_prenom, p_nom_famille, p_nom) then
    if nf = '' then
      mots := regexp_split_to_array(trim(coalesce(p_nom, '')), '\s+');
      n := array_length(mots, 1);
      nf := mots[n];
      if pr = '' then pr := array_to_string(mots[1:n - 1], ' '); end if;
    end if;
    return query select pr, nf, 'fiche'::text;
    return;
  end if;
  -- 2. Un seul mot sur la fiche : on le cherche dans l'e-mail
  w := coalesce(nullif(pr, ''), nullif(nf, ''), nullif(trim(coalesce(p_nom, '')), ''));
  if w is null or position('@' in coalesce(p_email, '')) = 0 then return; end if;
  wn := public.prenom_norm(w);
  loc := lower(split_part(p_email, '@', 1));
  loc := regexp_replace(loc, '\+.*$', '');
  loc := regexp_replace(loc, '[0-9]+', '', 'g');
  seg := array(select s from unnest(regexp_split_to_array(loc, '[._]+')) s where s ~ '[a-z]');
  if coalesce(array_length(seg, 1), 0) = 2 then
    if public.prenom_norm(seg[1]) = wn then autre := seg[2]; wpos := 1;
    elsif public.prenom_norm(seg[2]) = wn then autre := seg[1]; wpos := 2;
    end if;
  elsif coalesce(array_length(seg, 1), 0) = 1 then
    loc := replace(seg[1], '-', '');
    wn := replace(wn, ' ', '');
    if length(loc) - length(wn) >= 3 and left(loc, length(wn)) = wn then
      autre := substr(loc, length(wn) + 1); wpos := 1;
    elsif length(loc) - length(wn) >= 3 and right(loc, length(wn)) = wn then
      autre := left(loc, length(loc) - length(wn)); wpos := 2;
    end if;
  end if;
  if autre is null or autre !~ '^[a-z][a-z-]*[a-z]$' then return; end if;
  wf := case when w = upper(w) then initcap(lower(w)) else w end;
  af := initcap(autre);
  w_p := public.civilite_du_prenom(w) is not null;
  a_p := public.civilite_du_prenom(autre) is not null;
  if (w_p and not a_p) or (w_p = a_p and wpos = 1) then
    return query select wf, af, 'email'::text;
  else
    return query select af, wf, 'email'::text;
  end if;
end
$$;
grant execute on function public.denonciation_identite(text, text, text, text) to authenticated, service_role;

-- Nom utilisé pour chaque dénonciation (fiche ou e-mail)
alter table public.denonciations add column if not exists nom_utilise text;
alter table public.denonciations add column if not exists nom_source text;

create or replace function public.robot_denonciation_noter(p_cle text, p_ligne jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
  v_nom text;
  v_src text;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  select i.prenom || ' ' || i.nom, i.source into v_nom, v_src
  from public.contacts c, public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
  where c.id = (p_ligne->>'contact_id')::uuid;
  insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail, preuve,
                                    ref_externe, civilite, nom_utilise, nom_source)
  values ((p_ligne->>'contact_id')::uuid, p_ligne->>'plateforme', p_ligne->>'compte', p_ligne->>'promoteur',
          p_ligne->>'programme', p_ligne->>'ville', p_ligne->>'statut', left(p_ligne->>'detail', 4000),
          p_ligne->>'preuve', p_ligne->>'ref_externe', p_ligne->>'civilite', v_nom, v_src)
  returning denonciations.id into v_id;
  return v_id;
end
$$;

-- Civilité : déduite du prénom retenu (fiche ou e-mail)
create or replace function public.robot_civilite(p_cle text, p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select case c.civilite when 'Monsieur' then 'M.' when 'Madame' then 'Mme'
                   else (select public.civilite_du_prenom(i.prenom)
                         from public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i) end
          from public.contacts c where c.id = p_id);
end
$$;

-- Carré rouge / encadré du CRM : ce qui manque, le nom retenu, et l'écart éventuel.
create or replace function public.denonciation_manques(p_contact uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c public.contacts;
  manque text[] := '{}';
  n int;
  n_isel int;
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
  select count(*), count(*) filter (where plateforme = 'iselection') into n, n_isel
  from public.denonciation_cibles(p_contact);
  if n > 0 and i.prenom is null then
    manque := manque || 'nom';
  end if;
  if n_isel > 0 and coalesce(c.civilite, '') not in ('Monsieur', 'Madame')
     and public.civilite_du_prenom(i.prenom) is null then
    manque := manque || 'civilite';
  end if;
  -- Dénoncé sous un nom tiré de l'e-mail, que la fiche contredit maintenant
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

-- « C'est corrigé » côté nom : le vendeur a corrigé le nom chez les promoteurs.
create or replace function public.denonciation_nom_corrige(p_contact uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_nom text;
  n int;
begin
  select i.prenom || ' ' || i.nom into v_nom
  from public.contacts c, public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
  where c.id = p_contact and i.source = 'fiche'
    and (public.est_gerant() or public.paternite_peut_travailler(c, public.mon_prenom())
         or public.activite_conservee(c, public.mon_prenom()));
  if v_nom is null then
    raise exception 'fiche introuvable ou nom incomplet' using errcode = '42501';
  end if;
  update public.denonciations set nom_utilise = v_nom, nom_source = 'fiche',
         detail = left(coalesce(detail, '') || ' · nom corrigé chez le promoteur le ' || to_char(now() at time zone 'Europe/Paris', 'DD/MM/YYYY'), 4000)
  where contact_id = p_contact and nom_source = 'email';
  get diagnostics n = row_count;
  return n;
end
$$;
revoke all on function public.denonciation_nom_corrige(uuid) from public, anon;
grant execute on function public.denonciation_nom_corrige(uuid) to authenticated;

-- Les deux listes « à faire » : nom de la fiche, sinon déduit de l'e-mail ; rien si aucun des deux.
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
      and exists (select 1 from public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email))
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
  select x.id, i.prenom || ' ' || i.nom, c.email, c.telephone,
         x.plateforme, x.compte, x.nom, x.ville, x.cp, x.cp_obligatoire
  from cible x join public.contacts c on c.id = x.id
  cross join lateral public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
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
    and (x.plateforme <> 'iselection'
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(i.prenom) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;
