-- Stock réel de la pige par ville et par typologie, pour la page Annonces du CRM
-- (comparaison de nos annonces SeLoger avec la vraie offre des promoteurs).
-- Lots « libre » avec un prix, hors programmes SeLoger sans mandat ou à demander.
-- Paris est découpé par arrondissement (code postal). T5 = 5 pièces et plus.
-- Appliquée le 27/10/2026.
create or replace function public.annonces_stock()
returns table (cle text, ville text, cp text, type text, typo text, nb bigint, prix_min numeric, prix_med numeric, surf_min numeric, programme_min text)
language sql stable security invoker set search_path = public as $$
  select case when p.cp like '75%' then 'PARIS ' || (right(p.cp, 2)::int)::text else p.ville end as cle,
         min(p.ville)::text, min(p.cp)::text, l.type::text,
         'T' || least(l.pieces::int, 5) as typo,
         count(*),
         round(min(l.prix)::numeric),
         round((percentile_disc(0.5) within group (order by l.prix))::numeric),
         (array_agg(l.surf::numeric order by l.prix))[1],
         (array_agg(p.nom || ' (' || coalesce(p.promoteur, '?') || ')' order by l.prix))[1]
  from pige_lots l
  join pige_programmes p on p.id = l.programme_id
  where l.st = 'libre' and l.prix > 0 and l.pieces >= 1
    and l.type in ('Appartement', 'Maison')
    and coalesce(p.source, '') not in ('picking', 'nomandat')
  group by 1, l.type, 5
$$;

revoke all on function public.annonces_stock() from public, anon;
grant execute on function public.annonces_stock() to authenticated, service_role;
