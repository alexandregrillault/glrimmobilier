-- Dénonciation automatique hors Immo-Lead (09/11/2026) : Bouygues et Linkapp, validés par Alex.
-- Bouygues : une déclaration par programme (champ « Nom du programme »), adresse = ville cherchée
-- et son code postal (décision d'Alex). Linkapp : « Créer un contact », type « Lead » (décision
-- d'Alex), sans programme : une dénonciation par client et par promoteur, notée au registre sur
-- chaque programme du promoteur dans les villes du client (pastilles du CRM).
-- iSelection : civilité obligatoire (M., Mme, Mlle), jamais devinée → pas branché, en attente d'Alex.

alter table public.denonciation_comptes add column if not exists par_programme boolean not null default true;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, valide_le, note) values
  ('bouygues', 'bouygues',    true,  true,  '2026-11-09', 'Validé par Alex le 09/11/2026 : ville cherchée et code postal'),
  ('linkapp',  'linkapp_gbi', false, false, '2026-11-09', 'Validé par Alex le 09/11/2026 : contact de type Lead'),
  ('linkapp',  'linkapp_naca', false, false, '2026-11-09', 'Validé par Alex le 09/11/2026 : contact de type Lead'),
  ('linkapp',  'linkapp_infineo', false, false, '2026-11-09', 'Validé par Alex le 09/11/2026 : contact de type Lead'),
  ('linkapp',  'linkapp_primavefa', false, false, '2026-11-09', 'Validé par Alex le 09/11/2026 : contact de type Lead')
on conflict (plateforme, compte) do nothing;

-- Ce qu'il reste à dénoncer hors Immo-Lead (mêmes leads que robot_denonciations_a_faire).
-- Une ligne par (lead, compte) ; « programmes » = programmes du compte dans les villes du lead ;
-- pour un compte « par programme » (Bouygues), une ligne par programme.
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
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;
revoke all on function public.robot_denonciations_a_faire_plateformes(text, int) from public;
grant execute on function public.robot_denonciations_a_faire_plateformes(text, int) to anon, authenticated, service_role;

-- Le lancement horaire regarde aussi les plateformes.
create or replace function public.robot_lancer_denonciations()
returns text
language plpgsql security definer set search_path = public as $$
declare
  cle text;
  cle_robot text;
  n int;
begin
  if extract(hour from now() at time zone 'Europe/Paris') not between 8 and 20 then
    return 'hors 8 h - 20 h';
  end if;
  select value into cle_robot from public.app_secrets where name = 'robot_pige';
  select (select count(*) from public.robot_denonciations_a_faire(cle_robot, 500))
       + (select count(*) from public.robot_denonciations_a_faire_plateformes(cle_robot, 500)) into n;
  if n = 0 then
    return 'rien a denoncer';
  end if;
  select value into cle from public.app_secrets where name = 'github_robot';
  if cle is null or cle = '' then
    raise exception 'cle github_robot absente de app_secrets';
  end if;
  perform net.http_post(
    url := 'https://api.github.com/repos/alexandregrillault/glr-pige/actions/workflows/denonciation-auto.yml/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || cle,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'glr-robot-pige',
      'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main'));
  return 'robot lance (' || n || ' a denoncer)';
end
$$;
revoke all on function public.robot_lancer_denonciations() from public, anon, authenticated;
