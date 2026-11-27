-- Plans 2D : les deux portes du robot de conversion (session Pige et robots), avec la clé du robot.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE. À appliquer après 20261127_plans_2d.sql (appliquée le 27/11).
-- Choix de la session mère : comme tous les robots, celui-ci n'a pas de clé de service ; il passe par la
-- clé du robot (app_secrets « robot_pige ») et la clé publique.
--
--   1. neuf_plans_2d_erreurs : plans illisibles, pour ne pas les retenter à chaque passage tant que le plan
--      source n'a pas changé (demande de Pige et robots). Table à part : la table neuf_plans_2d n'est pas
--      modifiée (aucune contrainte retirée).
--   2. neuf_plans_2d_a_faire : exclut en plus les plans en erreur dont la source n'a pas changé.
--   3. robot_plans_2d_a_faire(p_cle, p_limite, p_apres) : la liste, par paquets triés par lot_id (anon,
--      vérifie la clé du robot comme les autres robot_*).
--   4. robot_plans_2d_enregistrer(...) : écrit la ligne de neuf_plans_2d (ou l'erreur) ; appelée par la
--      fonction edge plans2d-depot APRÈS le dépôt des images (service_role seulement).
--   5. robot_plans_2d_verifier(...) : la fonction edge vérifie la clé du robot et le lot avant tout dépôt
--      (service_role seulement).
-- Rien n'est retiré ni effacé.

-- 1. Plans illisibles ---------------------------------------------------------------------------
create table if not exists public.neuf_plans_2d_erreurs (
  lot_id     text primary key,
  source_url text not null,              -- plan_url qui n'a pas pu être converti
  erreur     text not null,
  le         timestamptz not null default now()
);
alter table public.neuf_plans_2d_erreurs enable row level security;
revoke all on public.neuf_plans_2d_erreurs from public, anon;
grant select on public.neuf_plans_2d_erreurs to authenticated;
grant all on public.neuf_plans_2d_erreurs to service_role;

-- 2. Liste de travail : mêmes colonnes, plans en erreur exclus tant que la source n'a pas changé -----
-- Note : documents_lot.maj_le n'est rempli qu'à la création (défaut now(), aucun déclencheur) ; la
-- comparaison qui compte est celle de plan_url.
create or replace view public.neuf_plans_2d_a_faire
with (security_invoker = true) as
  select l.id as lot_id, neuf_cle(l.id) as cle, d.plan_url, d.maj_le as plan_maj
    from pige_lots l
    join pige_programmes p on p.id = l.programme_id
    join neuf_villes v on v.etat = 'publiee' and v.dept = p.dept
     and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
     and (v.cps is null or p.cp = any(v.cps))
    join documents_lot d on d.lot_id = l.id and d.plan_url is not null
    left join neuf_plans_2d z on z.lot_id = l.id
    left join neuf_plans_2d_erreurs e on e.lot_id = l.id and e.source_url = d.plan_url
   where coalesce(p.source, '') not in ('picking', 'nomandat')
     and l.st in ('libre', 'option')
     and l.type in ('Appartement', 'Maison')
     and l.typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
     and e.lot_id is null
     and (z.lot_id is null or z.source_url is distinct from d.plan_url
          or (d.maj_le is not null and (z.source_maj is null or d.maj_le > z.source_maj)));
revoke all on public.neuf_plans_2d_a_faire from public, anon, authenticated;
grant select on public.neuf_plans_2d_a_faire to service_role;

-- 3. La liste pour le robot --------------------------------------------------------------------
create or replace function public.robot_plans_2d_a_faire(p_cle text, p_limite integer default 1000, p_apres text default null)
returns table (lot_id text, cle text, plan_url text, plan_maj timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
    select a.lot_id, a.cle, a.plan_url, a.plan_maj
      from public.neuf_plans_2d_a_faire a
     where p_apres is null or a.lot_id > p_apres
     order by a.lot_id
     limit least(greatest(coalesce(p_limite, 1000), 1), 5000);
end;
$$;
revoke all on function public.robot_plans_2d_a_faire(text, integer, text) from public;
grant execute on function public.robot_plans_2d_a_faire(text, integer, text) to anon, authenticated, service_role;

-- 4. Enregistrer une conversion (ou une erreur) --------------------------------------------------
-- p_pages > 0 : conversion réussie (images déjà déposées) ; p_pages = 0 avec p_erreur : plan illisible.
-- Réponse : 'ok' | 'inconnu' (lot sans ce plan, ou clé publique ne correspondant pas au lot).
create or replace function public.robot_plans_2d_enregistrer(
  p_cle text, p_lot_id text, p_cle_lot text, p_pages integer, p_source_url text, p_source_maj timestamptz, p_erreur text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if p_lot_id is null or neuf_cle(p_lot_id) is distinct from p_cle_lot
     or not exists (select 1 from documents_lot d where d.lot_id = p_lot_id and d.plan_url = p_source_url) then
    return 'inconnu';
  end if;
  if coalesce(p_pages, 0) between 1 and 8 then
    insert into neuf_plans_2d (lot_id, pages, source_url, source_maj, converti_le)
    values (p_lot_id, p_pages, p_source_url, p_source_maj, now())
    on conflict (lot_id) do update set pages = excluded.pages, source_url = excluded.source_url,
      source_maj = excluded.source_maj, converti_le = now();
    return 'ok';
  end if;
  if coalesce(p_pages, 0) = 0 and nullif(btrim(coalesce(p_erreur, '')), '') is not null then
    insert into neuf_plans_2d_erreurs (lot_id, source_url, erreur, le)
    values (p_lot_id, p_source_url, left(p_erreur, 500), now())
    on conflict (lot_id) do update set source_url = excluded.source_url, erreur = excluded.erreur, le = now();
    return 'ok';
  end if;
  return 'inconnu';
end;
$$;
revoke all on function public.robot_plans_2d_enregistrer(text, text, text, integer, text, timestamptz, text) from public, anon, authenticated;
grant execute on function public.robot_plans_2d_enregistrer(text, text, text, integer, text, timestamptz, text) to service_role;

-- 5. Vérification avant dépôt (fonction edge) : clé du robot, et lot qui a bien ce plan et cette clé publique.
-- Réponse : 'ok' | 'acces_refuse' | 'inconnu'.
create or replace function public.robot_plans_2d_verifier(p_cle text, p_lot_id text, p_cle_lot text, p_source_url text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_cle is null or length(p_cle) < 32
         or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then 'acces_refuse'
    when p_lot_id is null or neuf_cle(p_lot_id) is distinct from p_cle_lot
         or not exists (select 1 from public.documents_lot d where d.lot_id = p_lot_id and d.plan_url = p_source_url) then 'inconnu'
    else 'ok' end;
$$;
revoke all on function public.robot_plans_2d_verifier(text, text, text, text) from public, anon, authenticated;
grant execute on function public.robot_plans_2d_verifier(text, text, text, text) to service_role;
