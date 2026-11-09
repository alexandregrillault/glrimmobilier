-- Dénonciation automatique à l'arrivée des leads (demande d'Alex du 09/11/2026).
-- Chaque lead reçu est dénoncé, sur chaque compte extranet validé par Alex, pour tous les
-- programmes de la pige qui ont des lots libres dans les villes de sa fiche (ville de l'annonce
-- et villes cherchées, champ « lieu »). Le robot (glr-pige/robot/denonciation_auto.py) lit la
-- liste « à faire » par robot_denonciations_a_faire ; la base le lance toutes les heures de 8 h
-- à 20 h quand il y a quelque chose à faire (robot_lancer_denonciations, pg_cron).

-- Comptes extranets où la dénonciation automatique est validée (compte par compte, par Alex).
create table if not exists public.denonciation_comptes (
  plateforme     text not null,
  compte         text not null,
  actif          boolean not null default true,
  cp_obligatoire boolean not null default false,  -- Coffim : code postal de la ville cherchée
  valide_le      date,
  note           text,
  primary key (plateforme, compte)
);
alter table public.denonciation_comptes enable row level security;
drop policy if exists denonciation_comptes_gerant on public.denonciation_comptes;
create policy denonciation_comptes_gerant on public.denonciation_comptes
  for select to authenticated using (public.est_gerant());
grant select on public.denonciation_comptes to authenticated;
grant all on public.denonciation_comptes to service_role;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, valide_le, note) values
  ('immolead', 'care',       false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'coffim',     true,  '2026-11-09', 'Code postal obligatoire : celui de la ville cherchée (décision d''Alex)'),
  ('immolead', 'crennodeau', false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'emocom',     false, '2026-11-09', 'Distributeur : programme dans la 1re fenêtre, confirmation'),
  ('immolead', 'fair',       false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'logih',      false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'sepimo',     false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'spirit',     false, '2026-11-09', 'Validé par Alex le 09/11/2026'),
  ('immolead', 'wemo',       false, '2026-11-09', 'Distributeur : programme dans la 1re fenêtre, confirmation')
on conflict (plateforme, compte) do nothing;

-- Nom de ville comparable : minuscules, sans accents ni chiffres ni parenthèses, tirets = espaces.
create or replace function public.ville_norm(v text)
returns text language sql immutable as $$
  select regexp_replace(
           lower(translate(trim(regexp_replace(regexp_replace(coalesce(v, ''), '\(.*?\)', '', 'g'), '\d+', '', 'g')),
                           'éèêëàâäîïôöùûüçÉÈÊËÀÂÄÎÏÔÖÙÛÜÇ', 'eeeeaaaiioouuuceeeeaaaiioouuuc')),
           '[-'' ]+', ' ', 'g')
$$;

-- Ce qu'il reste à dénoncer : leads reçus depuis le 09/11/2026 0 h (début du service) et depuis
-- moins de 3 jours, hors « Ne plus contacter » et anciens leads importés ; une ligne par
-- (lead, compte, programme) pas encore envoyée, et abandonnée après 2 échecs.
create or replace function public.robot_denonciations_a_faire(p_cle text, p_limite int default 60)
returns table (contact_id uuid, nom_complet text, email text, telephone text,
               plateforme text, compte text, programme text, ville text, cp text, cp_obligatoire boolean)
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
                    where (d.contact_id = x.id or lower(c2.email) = lower(c.email))  -- lead en double dans le CRM
                      and d.compte = x.compte and d.programme = x.nom
                      and d.statut in ('envoyee', 'acceptee', 'refusee', 'deja_connu', 'a_faire_main'))
    and (select count(*) from public.denonciations d
         where d.contact_id = x.id and d.compte = x.compte and d.programme = x.nom and d.statut = 'echec') < 2
  order by x.compte, x.recu_le
  limit p_limite;
end
$$;
revoke all on function public.robot_denonciations_a_faire(text, int) from public;
grant execute on function public.robot_denonciations_a_faire(text, int) to anon, authenticated, service_role;

-- Lancement : toutes les heures de 8 h à 20 h (Paris), seulement s'il y a quelque chose à faire.
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
  select count(*) into n from public.robot_denonciations_a_faire(cle_robot, 500);
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

select cron.schedule('robot_denonciations_auto', '5 * * * *', 'select public.robot_lancer_denonciations()');
