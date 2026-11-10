-- Civilité pour la dénonciation iSelection (décision d'Alex du 10/11/2026, option 3) :
-- iSelection exige M., Mme ou Mlle. Le robot prend la civilité confirmée de la fiche
-- (contacts.civilite, « Monsieur » / « Madame », posée par le vendeur) ; à défaut, il la déduit
-- du prénom, seulement quand le prénom est quasi certain (98 % d'un même sexe dans le fichier
-- national des prénoms de l'Insee, 1900-2022, au moins 100 naissances). Prénom mixte ou inconnu :
-- rien, on attend le vendeur.
-- La civilité déduite ne sert QU'À la dénonciation : elle n'est jamais écrite dans
-- contacts.civilite, donc jamais utilisée dans un mail client (« civilité jamais devinée »).
-- La civilité envoyée est gardée au registre (denonciations.civilite) : si le vendeur confirme
-- ensuite l'autre civilité, le CRM le prévient (demande d'Alex).
-- Données : 20261110_prenoms_civilite_donnees.sql.

create table if not exists public.prenoms_civilite (
  prenom text primary key,          -- minuscules, sans accents, tirets et apostrophes en espaces
  civilite text not null check (civilite in ('M.', 'Mme')),
  naissances int
);
alter table public.prenoms_civilite enable row level security;
drop policy if exists prenoms_civilite_lecture on public.prenoms_civilite;
create policy prenoms_civilite_lecture on public.prenoms_civilite for select to authenticated using (true);
grant select on public.prenoms_civilite to authenticated;
grant all on public.prenoms_civilite to service_role;

create or replace function public.prenom_norm(t text)
returns text language sql immutable set search_path = public as $$
  select nullif(trim(regexp_replace(
    translate(lower(coalesce(t, '')), 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ-''’', 'aaaaaaceeeeiiiinooooouuuuyy   '),
    '\s+', ' ', 'g')), '')
$$;

-- 'M.', 'Mme' ou null. Prénom composé inconnu (« Sarah Helene ») : on essaie le premier prénom.
create or replace function public.civilite_du_prenom(p_prenom text)
returns text language plpgsql stable set search_path = public as $$
declare
  n text := public.prenom_norm(p_prenom);
  r text;
begin
  if n is null then return null; end if;
  select pc.civilite into r from public.prenoms_civilite pc where pc.prenom = n;
  if r is null and position(' ' in n) > 0 then
    select pc.civilite into r from public.prenoms_civilite pc where pc.prenom = split_part(n, ' ', 1);
  end if;
  return r;
end
$$;
grant execute on function public.prenom_norm(text) to authenticated, service_role;
grant execute on function public.civilite_du_prenom(text) to authenticated, service_role;

-- Civilité envoyée à la plateforme (iSelection), pour prévenir le vendeur d'une erreur.
alter table public.denonciations add column if not exists civilite text;

-- Civilité à envoyer pour un lead : confirmée par le vendeur, sinon déduite du prénom.
create or replace function public.robot_civilite(p_cle text, p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select case c.civilite when 'Monsieur' then 'M.' when 'Madame' then 'Mme'
                   else public.civilite_du_prenom(c.prenom) end
          from public.contacts c where c.id = p_id);
end
$$;
revoke all on function public.robot_civilite(text, uuid) from public;
grant execute on function public.robot_civilite(text, uuid) to anon, authenticated, service_role;

create or replace function public.robot_denonciation_noter(p_cle text, p_ligne jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail, preuve, ref_externe, civilite)
  values ((p_ligne->>'contact_id')::uuid, p_ligne->>'plateforme', p_ligne->>'compte', p_ligne->>'promoteur',
          p_ligne->>'programme', p_ligne->>'ville', p_ligne->>'statut', left(p_ligne->>'detail', 4000),
          p_ligne->>'preuve', p_ligne->>'ref_externe', p_ligne->>'civilite')
  returning denonciations.id into v_id;
  return v_id;
end
$$;

-- iSelection : pas de ligne à faire tant qu'aucune civilité n'est connue (ni confirmée, ni déduite).
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
    where c.recu_le >= greatest(now() - interval '3 days', timestamptz '2026-11-09 00:00:00+01')
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
           and (not x.par_programme or d.programme = x.cle) and d.statut = 'echec') < 2
    and (x.plateforme <> 'iselection'
         or c.civilite in ('Monsieur', 'Madame')
         or public.civilite_du_prenom(c.prenom) is not null)
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;

-- Compte iSelection : créé inactif ; activé une fois le robot à jour poussé.
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note) values
  ('iselection', 'iselection', false, false, false, '2026-11-10',
   'Validé par Alex le 09/11/2026 ; civilité confirmée ou déduite du prénom (décision du 10/11/2026)')
on conflict (plateforme, compte) do nothing;

-- « C'est corrigé » : le vendeur a corrigé la civilité chez iSelection ; le registre prend la
-- civilité confirmée de la fiche et le bandeau d'alerte disparaît. Réservé à qui peut modifier la fiche.
create or replace function public.denonciation_civilite_corrigee(p_contact uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_civ text;
  n int;
begin
  select case c.civilite when 'Monsieur' then 'M.' when 'Madame' then 'Mme' end into v_civ
  from public.contacts c
  where c.id = p_contact
    and (public.est_gerant() or public.paternite_peut_travailler(c, public.mon_prenom())
         or public.activite_conservee(c, public.mon_prenom()));
  if v_civ is null then
    raise exception 'fiche introuvable ou civilité non confirmée' using errcode = '42501';
  end if;
  update public.denonciations set civilite = v_civ,
         detail = left(coalesce(detail, '') || ' · civilité corrigée chez iSelection le ' || to_char(now() at time zone 'Europe/Paris', 'DD/MM/YYYY'), 4000)
  where contact_id = p_contact and plateforme = 'iselection' and civilite is not null and civilite <> v_civ;
  get diagnostics n = row_count;
  return n;
end
$$;
revoke all on function public.denonciation_civilite_corrigee(uuid) from public, anon;
grant execute on function public.denonciation_civilite_corrigee(uuid) to authenticated;
