-- Réponses des promoteurs lues dans les mails (demande d'Alex du 17/11/2026 : « je reçois toujours un mail de
-- confirmation de dénonciation acceptée ou refusée ») : le robot du Mac lit la boîte agl@ en lecture seule
-- (glr-pige/robot/denonciation_mails.py), retrouve la dénonciation et la passe en « acceptee » (pris en charge)
-- ou « refusee ». Seuls l'objet et la date du mail sont gardés (suivi_detail), jamais son contenu.

-- Dénonciations envoyées des p_jours derniers jours, avec de quoi reconnaître le client dans un mail.
create or replace function public.robot_denonciations_suivi(p_cle text, p_jours integer default 60)
returns table(id bigint, compte text, promoteur text, programme text, statut text, fait_le timestamptz,
              email text, telephone text, prenom text, nom text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if p_cle is null or length(p_cle) < 32 or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
  select d.id, d.compte, d.promoteur, d.programme, d.statut, d.fait_le, c.email, c.telephone, i.prenom, i.nom
  from public.denonciations d
  join public.contacts c on c.id = d.contact_id
  cross join lateral public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i
  where d.statut in ('envoyee', 'acceptee', 'refusee')
    and d.fait_le > now() - make_interval(days => greatest(1, least(p_jours, 365)));
end $$;

-- Réponse du promoteur notée sur une dénonciation.
create or replace function public.robot_denonciation_reponse(p_cle text, p_id bigint, p_statut text, p_detail text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
begin
  if p_cle is null or length(p_cle) < 32 or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if p_statut not in ('acceptee', 'refusee') then
    raise exception 'statut_invalide';
  end if;
  update public.denonciations
     set statut = p_statut, suivi_le = now(), suivi_detail = left(coalesce(p_detail, ''), 500),
         preuve_niveau = case when p_statut = 'acceptee' then 'liste' else preuve_niveau end
   where id = p_id and statut in ('envoyee', 'acceptee', 'refusee');
  return found;
end $$;

revoke all on function public.robot_denonciations_suivi(text, integer) from public;
revoke all on function public.robot_denonciation_reponse(text, bigint, text, text) from public;
grant execute on function public.robot_denonciations_suivi(text, integer) to anon, authenticated, service_role;
grant execute on function public.robot_denonciation_reponse(text, bigint, text, text) to anon, authenticated, service_role;
