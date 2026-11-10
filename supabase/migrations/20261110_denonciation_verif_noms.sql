-- Contrôle du nom dénoncé, chaque soir (demande d'Alex du 10/11/2026 : « une deuxième vérif à la fin
-- de chaque journée, pour être sûr que c'est bien dénoncé au bon nom, sinon la dénonce ne vaut rien »).
-- Le robot relit, chez le promoteur, le nom sous lequel chaque client a été dénoncé et le compare au
-- nom de la fiche CRM. Nom de référence = le nom de la fiche (complet, ou validé / corrigé par le
-- vendeur) ; un nom seulement déduit de l'e-mail n'est jamais imposé au promoteur : la dénonciation
-- reste « à valider » tant que le vendeur n'a pas cliqué « C'est bon » ou corrigé.
-- Statuts (denonciations.nom_verif) : ok, different (le promoteur a un autre nom), corrige (le robot a
-- corrigé le nom chez le promoteur), a_valider (nom tiré de l'e-mail, pas encore validé), illisible.
-- Immo-Lead d'abord (fiche detail-contact-N, formulaire « Modifier la fiche »).

alter table public.denonciations add column if not exists nom_promoteur text;
alter table public.denonciations add column if not exists nom_verif text;
alter table public.denonciations add column if not exists nom_verifie_le timestamptz;

-- Dénonciations à contrôler : envoyées ou acceptées depuis 30 jours, avec une fiche chez le promoteur,
-- jamais vérifiées, ou vérifiées sans être « ok », ou dont le nom de la fiche a changé depuis.
create or replace function public.robot_denonciations_a_verifier(p_cle text, p_plateforme text default 'immolead')
returns table (id bigint, compte text, ref_externe text, prenom text, nom text, source text, nom_promoteur text, nom_verif text)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
  select d.id, d.compte, d.ref_externe, i.prenom, i.nom,
         case when i.source = 'fiche' or coalesce(c.nom_confirme, false) then 'fiche' else i.source end,
         d.nom_promoteur, d.nom_verif
  from public.denonciations d
  join public.contacts c on c.id = d.contact_id
  left join lateral public.denonciation_identite(c.prenom, c.nom_famille, c.nom, c.email) i on true
  where d.plateforme = p_plateforme
    and d.statut in ('envoyee', 'acceptee')
    and coalesce(d.ref_externe, '') <> ''
    and d.fait_le >= now() - interval '30 days'
    and (d.nom_verif is distinct from 'ok'
         or public.prenom_norm(d.nom_promoteur) is distinct from public.prenom_norm(i.prenom || ' ' || i.nom))
  order by d.compte, d.id;
end
$$;
revoke all on function public.robot_denonciations_a_verifier(text, text) from public;
grant execute on function public.robot_denonciations_a_verifier(text, text) to anon, authenticated, service_role;

-- Résultat du contrôle d'une dénonciation.
create or replace function public.robot_denonciation_nom_verif(p_cle text, p_id bigint, p_nom_lu text, p_statut text, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  if p_statut not in ('ok', 'different', 'corrige', 'a_valider', 'illisible') then
    raise exception 'statut inconnu : %', p_statut;
  end if;
  update public.denonciations d
  set nom_promoteur = left(p_nom_lu, 200), nom_verif = p_statut, nom_verifie_le = now(),
      nom_utilise = case when p_statut in ('ok', 'corrige') then left(p_nom_lu, 200) else d.nom_utilise end,
      nom_source = case when p_statut in ('ok', 'corrige') then 'fiche' else d.nom_source end,
      detail = case when p_detail is null then d.detail else left(coalesce(d.detail, '') || ' · ' || p_detail, 4000) end
  where d.id = p_id;
end
$$;
revoke all on function public.robot_denonciation_nom_verif(text, bigint, text, text, text) from public;
grant execute on function public.robot_denonciation_nom_verif(text, bigint, text, text, text) to anon, authenticated, service_role;

-- Lancement chaque soir à 20 h 30, heure de Paris, après le dernier passage horaire (20 h).
-- « corriger » : activé le 10/11/2026 après le valide d'Alex sur l'essai (Morgane, Crenn & Odeau) ; le robot ne
-- corrige que pour compléter un nom, un nom vraiment différent reste à vérifier à la main.
create or replace function public.robot_lancer_verif_noms()
returns text
language plpgsql security definer set search_path = public as $$
declare
  cle text;
begin
  if extract(hour from now() at time zone 'Europe/Paris') <> 20 then
    return 'pas 20 h a Paris';
  end if;
  select value into cle from public.app_secrets where name = 'github_robot';
  if cle is null or cle = '' then
    raise exception 'cle github_robot absente de app_secrets';
  end if;
  perform net.http_post(
    url := 'https://api.github.com/repos/alexandregrillault/glr-pige/actions/workflows/denonciation-verif-noms.yml/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || cle,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'glr-robot-pige',
      'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('noter', 'true', 'corriger', 'true')));
  return 'controle des noms lance';
end
$$;
revoke all on function public.robot_lancer_verif_noms() from public, anon, authenticated;

select cron.schedule('robot_denonciation_noms_ete', '30 18 * * *', 'select public.robot_lancer_verif_noms()');
select cron.schedule('robot_denonciation_noms_hiver', '30 19 * * *', 'select public.robot_lancer_verif_noms()');
