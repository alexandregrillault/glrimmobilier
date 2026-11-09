-- Dénonciations visibles par le vendeur sur la fiche de ses clients et à la composition d'une
-- sélection (demande d'Alex du 09/11/2026). Un commercial lit les dénonciations des clients qu'il
-- peut déjà lire : la sous-requête sur contacts passe par les droits de contacts (paternité,
-- activité conservée), les gérants voient tout.

drop policy if exists denonciations_gerant on public.denonciations;
drop policy if exists denonciations_lecture on public.denonciations;
create policy denonciations_lecture on public.denonciations
  for select to authenticated
  using (public.est_gerant() or exists (select 1 from public.contacts c where c.id = denonciations.contact_id));
