-- Ymmea (10/11/2026) : « Nouveau prospect » exige un budget (tranche) et une typologie (T1…T5, Maison).
-- Budget = budget max de la fiche, sinon min, sinon prix de l'annonce ; typologie tirée du champ
-- « typologie » de la fiche (« Appartement 3 pièces », « T3 », « Maison 5 pièces »). Sans l'un ou l'autre,
-- pas de dénonciation Ymmea (le carré rouge de la fiche demande le budget).

create or replace function public.denonciation_typologie(p_typo text)
returns text language sql immutable set search_path = public as $$
  select case
    when p_typo is null or btrim(p_typo) = '' then null
    when p_typo ~* 'maison' then 'Maison'
    when p_typo ~* 'studio' then 'T1'
    when coalesce(substring(p_typo from '(\d+)\s*pi'), substring(p_typo from '[Tt]\s*(\d+)')) is null then null
    else 'T' || least(5, greatest(1, coalesce(substring(p_typo from '(\d+)\s*pi'), substring(p_typo from '[Tt]\s*(\d+)'))::int))
  end
$$;

create or replace function public.robot_contact_projet(p_cle text, p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_cle is null or length(p_cle) < 32
     or not exists (select 1 from public.app_secrets s where s.name = 'robot_pige' and s.value = p_cle) then
    raise exception 'acces_refuse' using errcode = '42501';
  end if;
  return (select jsonb_build_object(
            'budget', coalesce(nullif(c.budget_max, 0), nullif(c.budget_min, 0), nullif(c.prix_annonce, 0)::bigint),
            'typologie', public.denonciation_typologie(c.typologie))
          from public.contacts c where c.id = p_id);
end
$$;
revoke all on function public.robot_contact_projet(text, uuid) from public;
grant execute on function public.robot_contact_projet(text, uuid) to anon, authenticated, service_role;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('ymmea', 'ymmea', false, false, false, null,
        'Une dénonciation par client (Nouveau prospect) : budget et typologie obligatoires, secteur = ville cherchée (10/11/2026)')
on conflict do nothing;
