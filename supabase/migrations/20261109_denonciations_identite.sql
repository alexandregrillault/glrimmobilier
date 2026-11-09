-- Dénonciation hors Immo-Lead (Bouygues, Linkapp, iSelection, 09/11/2026) : ces formulaires
-- demandent le prénom et le nom dans deux champs séparés. Le robot les lit ici, avec la même clé
-- que robot_contact_denonciation (qui ne donne que le nom complet).

create or replace function public.robot_contact_identite(p_cle text, p_id uuid)
returns table (id uuid, prenom text, nom_famille text, nom text, civilite text, email text, telephone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return query
    select c.id, c.prenom, c.nom_famille, c.nom, c.civilite, c.email, c.telephone
    from public.contacts c
    where c.id = p_id and coalesce(c.statut, '') <> 'Stop';
end
$$;
revoke all on function public.robot_contact_identite(text, uuid) from public;
grant execute on function public.robot_contact_identite(text, uuid) to anon, authenticated, service_role;
