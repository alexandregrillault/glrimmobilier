-- 26/10/2026 — Identifiants des extranets pour le robot de pige (dépôt privé glr-pige).
--
-- Pourquoi : le robot qui fait la pige tout seul (GitHub Actions) doit se connecter aux
-- extranets avec les identifiants rangés dans la fiche promoteur du CRM. Plutôt que de lui
-- donner la clé service_role (accès total à la base), il reçoit une clé dédiée qui ne sert
-- qu'à une chose : lire login et mot de passe des promoteurs qu'il demande par leur nom.
--
-- La clé est tirée au hasard ici, dans la base, et n'apparaît nulle part ailleurs : Alex la
-- copie depuis la table app_secrets (ligne « robot_pige ») vers le secret GitHub
-- ROBOT_PIGE_CLE du dépôt glr-pige. Pour la changer : remplacer la valeur dans app_secrets,
-- puis le secret GitHub.

insert into public.app_secrets (name, value)
select 'robot_pige', encode(extensions.gen_random_bytes(32), 'hex')
where not exists (select 1 from public.app_secrets where name = 'robot_pige');

create or replace function public.robot_identifiants(p_cle text, p_noms text[])
returns table (nom text, login text, mot_de_passe text)
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
    select p.nom, p.login, p.mot_de_passe
    from public.promoteurs p
    where p.nom = any (p_noms) and p.actif;
end
$$;

revoke all on function public.robot_identifiants(text, text[]) from public;
grant execute on function public.robot_identifiants(text, text[]) to anon, authenticated, service_role;

-- Retour arrière :
-- drop function public.robot_identifiants(text, text[]);
-- delete from public.app_secrets where name = 'robot_pige';
