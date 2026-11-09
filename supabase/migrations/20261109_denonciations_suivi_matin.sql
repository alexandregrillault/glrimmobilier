-- Suivi des dénonciations tous les matins à 8 h, heure de Paris (demande d'Alex du 09/11/2026 :
-- ne pas attendre les piges du lundi, mercredi, vendredi). Même mécanisme que la pige
-- (20261030_robot_lancement.sql) : pg_cron appelle une RPC qui lance le workflow GitHub
-- denonciation-suivi.yml avec la clé github_robot ; deux horaires (été / hiver), seul celui
-- qui tombe à 8 h à Paris lance le robot.

create or replace function public.robot_lancer_suivi()
returns text
language plpgsql security definer set search_path = public as $$
declare
  cle text;
begin
  if extract(hour from now() at time zone 'Europe/Paris') <> 8 then
    return 'pas 8 h a Paris';
  end if;
  select value into cle from public.app_secrets where name = 'github_robot';
  if cle is null or cle = '' then
    raise exception 'cle github_robot absente de app_secrets';
  end if;
  perform net.http_post(
    url := 'https://api.github.com/repos/alexandregrillault/glr-pige/actions/workflows/denonciation-suivi.yml/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || cle,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'glr-robot-pige',
      'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('comptes', 'tous', 'noter', 'true')));
  return 'suivi lance';
end
$$;

revoke all on function public.robot_lancer_suivi() from public, anon, authenticated;

select cron.schedule('robot_denonciation_suivi_ete', '0 6 * * *', 'select public.robot_lancer_suivi()');
select cron.schedule('robot_denonciation_suivi_hiver', '0 7 * * *', 'select public.robot_lancer_suivi()');
