-- Plans 2D et plans de masse : jusqu'à 12 pages au lieu de 8.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE : elle remplace une contrainte de contrôle (« drop constraint »
-- puis « add constraint », aucune donnée touchée). Règle du dépôt : pas de « drop » sans l'accord explicite
-- d'Alex. Ne s'applique qu'avec son oui.
-- Constat de Pige et robots (27/11/2026) : les plans des maisons du Domaine Céladon (Maisons-Laffitte,
-- immolead_emocom:568180, 568183, 568192, 568195, 568198) font 10 ou 11 pages (niveaux, garage, coupes) ;
-- avec la limite de 8 ils étaient écartés comme « pas un plan de lot ».
--
--   1. neuf_plans_2d et neuf_masses_2d : contrainte « pages entre 1 et 12 » à la place de « entre 1 et 8 ».
--   2. robot_plans_2d_enregistrer et robot_masses_2d_enregistrer : acceptent 1 à 12 pages.
--   3. Les 5 maisons du Domaine Céladon remises dans la liste du robot, SANS suppression : leur ligne de
--      neuf_plans_2d_erreurs garde sa trace, mais son adresse est marquée « #relance » ; elle ne correspond
--      plus au plan, donc le lot revient dans neuf_plans_2d_a_faire.
-- Avec : plans2d-depot v2 (12 pages au plus) et plans-3d v9 (page demandée jusqu'à 12), au même « déploie ».

-- 1. Contraintes -------------------------------------------------------------------------------
alter table public.neuf_plans_2d drop constraint if exists neuf_plans_2d_pages_check;
alter table public.neuf_plans_2d add constraint neuf_plans_2d_pages_check check (pages between 1 and 12);
alter table public.neuf_masses_2d drop constraint if exists neuf_masses_2d_pages_check;
alter table public.neuf_masses_2d add constraint neuf_masses_2d_pages_check check (pages between 1 and 12);

-- 2. Enregistrement par le robot : 1 à 12 pages ---------------------------------------------------
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
  if coalesce(p_pages, 0) between 1 and 12 then
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

create or replace function public.robot_masses_2d_enregistrer(
  p_cle text, p_programme_id text, p_cle_prog text, p_pages integer, p_source_url text, p_source_maj timestamptz, p_erreur text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.robot_masses_2d_verifier(p_cle, p_programme_id, p_cle_prog, p_source_url) = 'acces_refuse' then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if public.robot_masses_2d_verifier(p_cle, p_programme_id, p_cle_prog, p_source_url) <> 'ok' then
    return 'inconnu';
  end if;
  if coalesce(p_pages, 0) between 1 and 12 then
    insert into neuf_masses_2d (programme_id, pages, source_url, source_maj, converti_le)
    values (p_programme_id, p_pages, p_source_url, p_source_maj, now())
    on conflict (programme_id) do update set pages = excluded.pages, source_url = excluded.source_url,
      source_maj = excluded.source_maj, converti_le = now();
    return 'ok';
  end if;
  if coalesce(p_pages, 0) = 0 and nullif(btrim(coalesce(p_erreur, '')), '') is not null then
    insert into neuf_masses_2d_erreurs (programme_id, source_url, erreur, le)
    values (p_programme_id, p_source_url, left(p_erreur, 500), now())
    on conflict (programme_id) do update set source_url = excluded.source_url, erreur = excluded.erreur, le = now();
    return 'ok';
  end if;
  return 'inconnu';
end;
$$;
revoke all on function public.robot_masses_2d_enregistrer(text, text, text, integer, text, timestamptz, text) from public, anon, authenticated;
grant execute on function public.robot_masses_2d_enregistrer(text, text, text, integer, text, timestamptz, text) to service_role;

-- 3. Les 5 maisons du Domaine Céladon : retour dans la liste du robot, sans rien supprimer -----------
update public.neuf_plans_2d_erreurs
   set source_url = source_url || '#relance', erreur = erreur || ' (relancé le 27/11/2026 : limite passée à 12 pages)'
 where lot_id in ('immolead_emocom:568180', 'immolead_emocom:568183', 'immolead_emocom:568192',
                  'immolead_emocom:568195', 'immolead_emocom:568198')
   and source_url not like '%#relance';
