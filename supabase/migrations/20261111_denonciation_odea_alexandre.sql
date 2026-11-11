-- ODEA (11/11/2026, décision d'Alex : « pour mes clients fais-le sur le téléphone de Théophile ») : les
-- clients d'Alexandre sont dénoncés à son nom et avec son e-mail, et le téléphone de Théophile (la fiche
-- vendeur d'Alexandre n'a pas de téléphone). Nour arrête : sans téléphone dans sa fiche, pas d'ODEA.
create or replace function public.denonciation_vendeur(p_vendeur text)
returns jsonb language sql stable security definer set search_path = public as $$
  with v as (
    select e, regexp_replace(coalesce(e->>'telephone', ''), '\D', '', 'g') as tel
    from public.dashboard_data d, jsonb_array_elements(d.vendeurs) e
    where d.id = 'main'
  ),
  cible as (
    select v.e,
           case when length(v.tel) >= 10 then v.tel
                when public.prenom_norm(v.e->>'prenom') = public.prenom_norm('Alexandre')
                  then (select t.tel from v t where public.prenom_norm(t.e->>'prenom') = public.prenom_norm('Théophile')
                          and length(t.tel) >= 10 limit 1)
           end as tel
    from v
    where p_vendeur is not null and public.prenom_norm(v.e->>'prenom') = public.prenom_norm(p_vendeur)
  )
  select jsonb_build_object('nom', trim(coalesce(e->>'prenom', '') || ' ' || coalesce(e->>'nom', '')),
                            'email', trim(e->>'email'), 'telephone', tel)
  from cible
  where coalesce(e->>'email', '') ~ '@' and tel is not null
  limit 1
$$;
revoke all on function public.denonciation_vendeur(text) from public, anon, authenticated;
grant execute on function public.denonciation_vendeur(text) to service_role;
