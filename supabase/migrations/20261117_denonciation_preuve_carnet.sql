-- Immo-Lead « Client déjà dans notre carnet Immo-Lead, demande sur ce programme déjà présente » : le client est
-- bien chez le promoteur, donc vert (preuve 'liste'), pas « à vérifier » (contrôle du 17/11/2026).
create or replace function public.denonciation_preuve_niveau(p_statut text, p_detail text)
returns text language sql immutable as $$
  select case
    when p_statut not in ('envoyee', 'acceptee') then null
    when p_detail ~* '(retrouv|Enregistrer le contact|déjà dans notre carnet)' then 'liste'
    else 'message' end
$$;
update public.denonciations set preuve_niveau = 'liste'
where statut = 'envoyee' and preuve_niveau = 'message' and detail ~* 'déjà dans notre carnet';
