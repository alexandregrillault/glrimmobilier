-- 30/10/2026 — Lancement du robot de pige par Supabase.
--
-- Pourquoi : les lancements programmés de GitHub arrivent 5 à 6 h en retard (28 et 30/10/2026),
-- et le Mac peut être éteint à 6 h. Supabase tourne en permanence : son minuteur (pg_cron) demande
-- à GitHub de lancer les deux robots tout de suite (workflow_dispatch), lundi, mercredi, vendredi
-- à 6 h 17, heure de Paris.
--
-- Prérequis, à faire par Alex AVANT cette migration : créer sur GitHub une clé limitée au dépôt
-- glr-pige (Fine-grained token, droit Actions : lecture et écriture), puis la ranger dans la base
-- depuis l'éditeur SQL. Elle ne passe ni par ce fichier, ni par la conversation :
--   insert into public.app_secrets (name, value) values ('github_robot', '<la clé>')
--   on conflict (name) do update set value = excluded.value, updated_at = now();
--
-- Essai sans attendre lundi : select public.robot_lancer(true);  → lance la seule source Kaufman.
-- Réponse de GitHub : select status_code, content from net._http_response order by created desc limit 2;
-- (204 = accepté)

create or replace function public.robot_lancer(p_essai boolean default false)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  cle text;
  entetes jsonb;
  depot constant text := 'https://api.github.com/repos/alexandregrillault/glr-pige/actions/workflows/';
begin
  -- GitHub et pg_cron comptent en UTC : deux horaires sont déclarés (été, hiver), celui qui ne
  -- tombe pas à 6 h à Paris ce jour-là ne fait rien.
  if not p_essai and extract(hour from now() at time zone 'Europe/Paris') <> 6 then
    return 'pas 6 h a Paris';
  end if;
  select value into cle from public.app_secrets where name = 'github_robot';
  if cle is null or cle = '' then
    raise exception 'cle github_robot absente de app_secrets';
  end if;
  entetes := jsonb_build_object(
    'Authorization', 'Bearer ' || cle,
    'Accept', 'application/vnd.github+json',
    'X-GitHub-Api-Version', '2022-11-28',
    'User-Agent', 'glr-robot-pige',
    'Content-Type', 'application/json');
  if p_essai then
    perform net.http_post(url := depot || 'pige-plateformes.yml/dispatches', headers := entetes,
      body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('sources', 'kaufman')));
    return 'essai lance (kaufman)';
  end if;
  perform net.http_post(url := depot || 'pige-immolead.yml/dispatches', headers := entetes,
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('comptes', 'tous')));
  perform net.http_post(url := depot || 'pige-plateformes.yml/dispatches', headers := entetes,
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('sources', 'tous')));
  return 'robots lances';
end
$$;

-- Personne d'autre que le minuteur et l'éditeur SQL ne peut lancer le robot.
revoke all on function public.robot_lancer(boolean) from public, anon, authenticated;

select cron.schedule('robot_pige_ete', '17 4 * * 1,3,5', $$select public.robot_lancer()$$);
select cron.schedule('robot_pige_hiver', '17 5 * * 1,3,5', $$select public.robot_lancer()$$);

-- Retour arrière :
-- select cron.unschedule('robot_pige_ete'); select cron.unschedule('robot_pige_hiver');
-- drop function public.robot_lancer(boolean);
-- delete from public.app_secrets where name = 'github_robot';
