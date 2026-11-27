-- Plans 3D : la fiche du lead dit quel programme et quels logements le client a regardés en 3D.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE. À appliquer après 20261127_plans_3d.sql (appliquée le 27/11).
-- Demande de la session Site, relayée par la mère : le site n'envoie que des clés de 12 caractères ;
-- Alex doit savoir, sur la fiche, quel logement intéressait le client.
--
--   1. neuf_3d_programme(p_cle) : nom et ville du programme, lus en base (la note ne dépend plus du
--      texte envoyé par la page).
--   2. neuf_3d_vues : premier passage de chaque jeton sur chaque logement.
--   3. neuf_3d_acces : à la première ouverture d'un logement par un client, une ligne est ajoutée aux
--      notes de sa fiche : « [27/11/2026] Visite 3D : lot A001 (T3, 62 m²), Esprit Valmy à Colombes ».
--      Une ligne par logement et par client, jamais deux fois. L'immeuble seul n'ajoute rien.
--      Écriture faite par la base (clé de service) : ne touche ni au vendeur ni aux délais de paternité.
-- Rien n'est retiré ni effacé.

create or replace function public.neuf_3d_programme(p_cle text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('nom', p.nom, 'ville', p.ville)
    from pige_programmes p
   where neuf_cle(p.id) = p_cle
   limit 1;
$$;
revoke all on function public.neuf_3d_programme(text) from public, anon, authenticated;
grant execute on function public.neuf_3d_programme(text) to service_role;

create table if not exists public.neuf_3d_vues (
  empreinte text not null,
  lot_id    text not null,
  vu_le     timestamptz not null default now(),
  primary key (empreinte, lot_id)
);
alter table public.neuf_3d_vues enable row level security;
revoke all on public.neuf_3d_vues from public, anon, authenticated;
grant all on public.neuf_3d_vues to service_role;

create or replace function public.neuf_3d_acces(p_programme text, p_lot text, p_empreinte text, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_par_jeton constant integer := 40;
  c_par_ip    constant integer := 60;
  v_jour    date := (now() at time zone 'Europe/Paris')::date;
  v_fich    text;
  v_lot     text;
  v_prog    text;
  v_nj      integer;
  v_ni      integer;
  v_contact uuid;
  v_n       integer;
  v_ligne   text;
begin
  select contact_id into v_contact
    from neuf_3d_jetons where empreinte = p_empreinte and expire_le > now();
  if p_empreinte is null or not found then
    return jsonb_build_object('statut', 'jeton');
  end if;

  insert into neuf_3d_appels (qui, jour, n) values ('j:' || p_empreinte, v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_nj;
  insert into neuf_3d_appels (qui, jour, n) values ('ip:' || coalesce(p_ip, 'inconnue'), v_jour, 1)
  on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_ni;
  if v_nj > c_par_jeton or v_ni > c_par_ip then
    return jsonb_build_object('statut', 'limite');
  end if;

  select x.fichier, x.lot_id, x.programme_id into v_fich, v_lot, v_prog
    from neuf_visites_3d x
   where x.actif
     and neuf_cle(x.programme_id) = p_programme
     and ((p_lot is null and x.lot_id is null) or (p_lot is not null and x.lot_id is not null and neuf_cle(x.lot_id) = p_lot))
   limit 1;
  if v_fich is null then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  -- Première ouverture de ce logement par ce client : une ligne dans les notes de sa fiche.
  if v_lot is not null and v_contact is not null then
    insert into neuf_3d_vues (empreinte, lot_id) values (p_empreinte, v_lot) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      select '[' || to_char(now() at time zone 'Europe/Paris', 'DD/MM/YYYY') || '] Visite 3D : lot ' || l.n
             || coalesce(' (' || l.typo || coalesce(', ' || replace(rtrim(to_char(l.surf, 'FM999990.9'), '.'), '.', ',') || ' m²', '') || ')', '')
             || coalesce(', ' || p.nom, '') || coalesce(' à ' || p.ville, '')
        into v_ligne
        from pige_lots l join pige_programmes p on p.id = l.programme_id
       where l.id = v_lot;
      if v_ligne is not null then
        update contacts set notes = case when coalesce(notes, '') = '' then v_ligne else notes || E'\n' || v_ligne end
         where id = v_contact;
      end if;
    end if;
  end if;

  return jsonb_build_object('statut', 'ok', 'fichier', v_fich);
end;
$$;
revoke all on function public.neuf_3d_acces(text, text, text, text) from public, anon, authenticated;
grant execute on function public.neuf_3d_acces(text, text, text, text) to service_role;
