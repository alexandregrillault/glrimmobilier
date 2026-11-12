-- Contrôle des plans gardés par le CRM (documents_lot), 12/11/2026, demande d'Alex :
-- « un duplex = 2 étages, un triplex = 3, jamais des plans qui n'ont aucun rapport », pour TOUS les promoteurs.
-- Pour Nexity, Immo-Lead, Cogedim, Green City, Accueil, European Homes, Pirphi, Groupe SM (et les lots
-- Station 9 sans plan dans la pige), le seul plan est la copie du CRM : la pige la relit (plans_niveaux.py --copies).
-- Accès réservé à la clé du robot de pige (app_secrets 'robot_pige'), comme les autres RPC robot_*.

-- Journal des corrections : l'ancien plan est toujours gardé, pour revenir en arrière.
create table if not exists public.documents_lot_corrections (
  id bigint generated always as identity primary key,
  lot_id text not null,
  avant text,
  apres text not null,
  raison text,
  le timestamptz not null default now()
);
alter table public.documents_lot_corrections enable row level security;
revoke all on public.documents_lot_corrections from anon, authenticated;
grant select on public.documents_lot_corrections to authenticated;
grant all on public.documents_lot_corrections to service_role;
create policy documents_lot_corrections_gerants on public.documents_lot_corrections
  for select to authenticated using (public.est_gerant());

-- Les copies de plans des lots demandés (par préfixe de source : 'nexity', 'immolead_wemo'…).
create or replace function public.robot_plans_copies(p_cle text, p_sources text[])
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_object_agg(d.lot_id, case when jsonb_typeof(d.plan_urls) = 'array' and jsonb_array_length(d.plan_urls) > 0
                                           then d.plan_urls else jsonb_build_array(d.plan_url) end)
    from public.documents_lot d
    where d.plan_url is not null and split_part(d.lot_id, ':', 1) = any(p_sources)), '{}'::jsonb);
end $$;

-- Remplace la copie du plan d'un lot par le plan d'un autre lot du même programme qui porte son numéro.
-- Ne fait rien si la copie a changé entre-temps (p_avant) ; l'ancien plan part au journal.
create or replace function public.robot_plan_copie_corriger(p_cle text, p_lot text, p_avant text, p_apres text, p_raison text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare n int;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  update public.documents_lot set plan_url = p_apres, plan_urls = null, maj_le = now()
   where lot_id = p_lot and plan_url = p_avant;
  get diagnostics n = row_count;
  if n = 1 then
    insert into public.documents_lot_corrections (lot_id, avant, apres, raison) values (p_lot, p_avant, p_apres, p_raison);
  end if;
  return n = 1;
end $$;

revoke all on function public.robot_plans_copies(text, text[]) from public;
revoke all on function public.robot_plan_copie_corriger(text, text, text, text, text) from public;
grant execute on function public.robot_plans_copies(text, text[]) to anon, authenticated, service_role;
grant execute on function public.robot_plan_copie_corriger(text, text, text, text, text) to anon, authenticated, service_role;

-- Même jour, accord d'Alex (« retire-le », Studéa lot 208 : un procès-verbal d'AG rangé comme plan) :
-- p_apres null = retirer la copie d'un document qui n'est pas un plan ; l'ancien lien reste au journal.
alter table public.documents_lot_corrections alter column apres drop not null;
-- (robot_plan_copie_corriger inchangée dans sa forme : un p_apres null met plan_url à null.)
