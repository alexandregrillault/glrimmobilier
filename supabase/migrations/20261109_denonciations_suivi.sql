-- Dénonciations : envoi puis suivi de la réponse du promoteur (décision d'Alex du 09/11/2026).
-- Certains promoteurs mettent du temps à valider : à l'envoi, statut « envoyee » ; le robot de pige
-- relit ensuite la dénonciation sur l'extranet (lundi, mercredi, vendredi) et passe la ligne en
-- « acceptee » ou « refusee » (client déjà connu). « enregistree » (1re dénonciation Care du 09/11)
-- devient « envoyee ». Plus de capture quand tout va bien : seulement en cas d'échec.

alter table public.denonciations add column if not exists ref_externe text;   -- ex. immolead detail-contact-4380361
alter table public.denonciations add column if not exists suivi_le timestamptz; -- dernière relecture sur l'extranet
alter table public.denonciations add column if not exists suivi_detail text;    -- ce que l'extranet affiche

alter table public.denonciations drop constraint if exists denonciations_statut_check;
update public.denonciations set statut = 'envoyee' where statut = 'enregistree';
update public.denonciations set ref_externe = substring(detail from 'detail-contact-[0-9]+')
  where ref_externe is null and detail ~ 'detail-contact-[0-9]+';
alter table public.denonciations add constraint denonciations_statut_check
  check (statut in ('essai', 'envoyee', 'acceptee', 'refusee', 'deja_connu', 'echec', 'a_faire_main'));

-- Le robot note l'envoi : ref_externe en plus.
create or replace function public.robot_denonciation_noter(p_cle text, p_ligne jsonb)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail, preuve, ref_externe)
  values ((p_ligne->>'contact_id')::uuid, p_ligne->>'plateforme', p_ligne->>'compte', p_ligne->>'promoteur',
          p_ligne->>'programme', p_ligne->>'ville', p_ligne->>'statut', left(p_ligne->>'detail', 4000),
          p_ligne->>'preuve', p_ligne->>'ref_externe')
  returning denonciations.id into v_id;
  return v_id;
end
$$;

-- Dénonciations envoyées et pas encore tranchées, pour un compte (le robot les relit).
create or replace function public.robot_denonciations_en_attente(p_cle text, p_plateforme text, p_compte text)
returns table (id bigint, ref_externe text, programme text, fait_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
    select d.id, d.ref_externe, d.programme, d.fait_le from public.denonciations d
    where d.plateforme = p_plateforme and d.compte = p_compte and d.statut = 'envoyee' and d.ref_externe is not null
    order by d.fait_le;
end
$$;

-- Le robot note ce qu'il a relu : nouveau statut (acceptee, refusee) ou seulement la date de relecture.
create or replace function public.robot_denonciation_suivi(p_cle text, p_id bigint, p_statut text, p_detail text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if p_statut is not null and p_statut not in ('envoyee', 'acceptee', 'refusee') then
    raise exception 'statut_inconnu';
  end if;
  update public.denonciations
     set statut = coalesce(p_statut, statut), suivi_le = now(), suivi_detail = left(p_detail, 2000)
   where id = p_id and statut = 'envoyee';
end
$$;

revoke all on function public.robot_denonciations_en_attente(text, text, text) from public;
revoke all on function public.robot_denonciation_suivi(text, bigint, text, text) from public;
grant execute on function public.robot_denonciations_en_attente(text, text, text) to anon, authenticated, service_role;
grant execute on function public.robot_denonciation_suivi(text, bigint, text, text) to anon, authenticated, service_role;
