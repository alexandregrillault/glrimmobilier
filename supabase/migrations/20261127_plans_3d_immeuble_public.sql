-- Plans 3D : l'immeuble se voit sans formulaire, les plans des logements restent derrière le formulaire.
--
-- PRÉPARÉE le 27/11/2026, NON APPLIQUÉE.
-- Décision d'Alex du 27/11/2026 (session mère) : « je veux ue le client voit le nouvelle immeuble qu'on
-- a mis en place et il pourra voir les plans uniquement si il a un compte. »
--
-- neuf_3d_acces : le jeton n'est plus exigé quand on demande l'immeuble (p_lot vide). La limite par
-- adresse (60 fichiers par jour) s'applique toujours ; la limite par jeton aussi quand il y en a un.
-- Sans effet tant que la fonction plans-3d en ligne (version 1) exige un jeton : on peut l'appliquer
-- avant le déploiement de la version 2.
-- Sauvegarde de la version en place (avec la note des logements) dans fonctions_backup_20261127.

insert into public.fonctions_backup_20261127 (nom, definition)
select 'neuf_3d_acces v2 (note des logements)', pg_get_functiondef('public.neuf_3d_acces(text,text,text,text)'::regprocedure)
on conflict (nom) do nothing;

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
  v_nj      integer := 0;
  v_ni      integer;
  v_contact uuid;
  v_jeton   boolean := false;
  v_n       integer;
  v_ligne   text;
begin
  if p_empreinte is not null then
    select contact_id into v_contact
      from neuf_3d_jetons where empreinte = p_empreinte and expire_le > now();
    v_jeton := found;
  end if;
  -- Les plans d'un logement : formulaire obligatoire. L'immeuble : ouvert à tous (décision du 27/11/2026).
  if p_lot is not null and not v_jeton then
    return jsonb_build_object('statut', 'jeton');
  end if;

  if v_jeton then
    insert into neuf_3d_appels (qui, jour, n) values ('j:' || p_empreinte, v_jour, 1)
    on conflict (qui, jour) do update set n = neuf_3d_appels.n + 1 returning n into v_nj;
  end if;
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
