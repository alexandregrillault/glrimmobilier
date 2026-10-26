-- 26/10/2026 — Règles arbitrées par Alex :
-- 1. Un client qui réagit sur sa sélection (option, intéressé, commentaire…) relance
--    la paternité de son vendeur pour 14 jours, même si le lead était tombé dans le pool.
--    Si la sélection a été faite par un autre vendeur que celui qui suit le client
--    aujourd'hui, l'auteur de la sélection est tenu au courant (activité conservée).
-- 2. Un lead pris dans le pool repart en « Nouveau », avec une note : ancien statut
--    et qui le suivait.
-- 3. Les liens de rendez-vous actifs suivent le vendeur du client (sauf pendant une
--    compétition ouverte, où c'est justement le rendez-vous qui départage).

-- 0. Sauvegarde des fonctions modifiées
create table if not exists public.fonctions_backup_20261026 (proname text, def text, sauve_le timestamptz default now());
alter table public.fonctions_backup_20261026 enable row level security;
revoke all on public.fonctions_backup_20261026 from anon;
grant all on public.fonctions_backup_20261026 to authenticated, service_role;
insert into public.fonctions_backup_20261026 (proname, def)
select p.proname, pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('selection_reaction_client', 'pool_prendre', 'contacts_reattribution_activites');

-- 1a. Auteur d'une sélection : figé à la création (selections.vendeur, lui, suit le client)
alter table public.selections add column if not exists auteur text;
update public.selections set auteur = vendeur where auteur is null;

create or replace function public.selections_auteur() returns trigger
language plpgsql set search_path = public as $$
begin
  new.auteur := coalesce(nullif(btrim(coalesce(new.auteur, '')), ''), new.vendeur);
  return new;
end $$;
create trigger trg_selections_auteur before insert on public.selections
  for each row execute function public.selections_auteur();

-- 1b. Réaction du client : paternité relancée + auteur prévenu
create or replace function public.selection_reaction_client() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  -- Ordre de force voulu par Alex (13/10/2026) : option > intéressé > commentaire > à discuter > (infos) > adresse. « Pas pour moi » est ignoré.
  ordre text[] := array['option','interesse','commentaire','discuter','infos','adresse'];
  k text; n jsonb; o jsonb;
  neufs text[] := array[]::text[];
  anciens text[] := array[]::text[];
  tous text[] := array[]::text[];
  parts text[] := array[]::text[];
  x text; titre text; extrait text := ''; ancien_extrait text := ''; c record; jour date; liste jsonb; trace text; ex jsonb; trace_parts text[] := array[]::text[];
  force_n int; suivi text; auteur text;
begin
  if new.contact_id is null or new.avis is not distinct from old.avis then return new; end if;
  if jsonb_typeof(new.avis) <> 'object' then return new; end if;

  for k in select jsonb_object_keys(new.avis) loop
    if k = 'rdv' then continue; end if;
    n := new.avis -> k;
    if jsonb_typeof(n) <> 'object' then continue; end if;
    o := case when jsonb_typeof(old.avis) = 'object' and jsonb_typeof(old.avis -> k) = 'object' then old.avis -> k else '{}'::jsonb end;

    if n->>'choix' = 'interesse'    and (n->>'choix_date') is distinct from (o->>'choix_date') then neufs := array_append(neufs, 'interesse'::text); end if;
    if n->>'choix' = 'a_discuter'   and (n->>'choix_date') is distinct from (o->>'choix_date') then neufs := array_append(neufs, 'discuter'::text); end if;
    if n->>'option' = 'true'        and (n->>'option_date') is distinct from (o->>'option_date') then neufs := array_append(neufs, 'option'::text); end if;
    if n->>'infos' = 'true'         and (n->>'infos_date') is distinct from (o->>'infos_date') then neufs := array_append(neufs, 'infos'::text); end if;
    if n->>'adresse_demandee' = 'true' and (n->>'adresse_date') is distinct from (o->>'adresse_date') then neufs := array_append(neufs, 'adresse'::text); end if;
    if coalesce(btrim(n->>'commentaire'), '') <> '' and (n->>'commentaire_date') is distinct from (o->>'commentaire_date') then
      neufs := array_append(neufs, 'commentaire'::text); extrait := left(btrim(n->>'commentaire'), 70);
    end if;
  end loop;

  if coalesce(array_length(neufs, 1), 0) = 0 then return new; end if;

  select id, statut, notes, activites, vendeur into c from public.contacts where id = new.contact_id;
  if not found or c.statut in ('Vendu', 'Perdu', 'Non qualifié', 'Stop') then return new; end if;

  select e into ex from jsonb_array_elements(case when jsonb_typeof(c.activites) = 'array' then c.activites else '[]'::jsonb end) e
   where e->>'id' = 'reaction_client' limit 1;
  if ex is not null and jsonb_typeof(ex->'reactions') = 'array' then
    select coalesce(array_agg(v), array[]::text[]) into anciens from jsonb_array_elements_text(ex->'reactions') v;
    ancien_extrait := coalesce(ex->>'extrait', '');
  end if;
  if extrait = '' then extrait := ancien_extrait; end if;

  foreach x in array ordre loop
    if x = any(neufs) or x = any(anciens) then tous := array_append(tous, x); end if;
  end loop;
  force_n := array_position(ordre, tous[1]);

  foreach x in array tous loop
    parts := array_append(parts, (case x
      when 'option' then 'option demandée'
      when 'interesse' then 'intéressé'
      when 'commentaire' then 'commentaire « ' || extrait || (case when length(extrait) >= 70 then '…' else '' end) || ' »'
      when 'discuter' then 'souhaite en discuter'
      when 'infos' then 'demande d''informations'
      else 'adresse demandée' end)::text);
  end loop;
  foreach x in array ordre loop
    if x = any(neufs) then
      trace_parts := array_append(trace_parts, (case x
        when 'option' then 'option demandée'
        when 'interesse' then 'intéressé'
        when 'commentaire' then 'commentaire « ' || extrait || (case when length(extrait) >= 70 then '…' else '' end) || ' »'
        when 'discuter' then 'souhaite en discuter'
        when 'infos' then 'demande d''informations'
        else 'adresse demandée' end)::text);
    end if;
  end loop;

  titre := 'Réaction du client sur sa sélection — ' || array_to_string(parts, ' · ');
  jour := (now() at time zone 'Europe/Paris')::date;
  suivi := nullif(btrim(coalesce(c.vendeur, '')), '');
  auteur := nullif(btrim(coalesce(new.auteur, '')), '');

  -- La réaction remplace le simple « retour » du même client (elle dit déjà qu'il est revenu)
  select coalesce(jsonb_agg(e), '[]'::jsonb) into liste
    from jsonb_array_elements(case when jsonb_typeof(c.activites) = 'array' then c.activites else '[]'::jsonb end) e
   where e->>'id' is distinct from 'reaction_client' and e->>'id' is distinct from 'retour_client'
     and (auteur is null or e->>'id' is distinct from 'reaction_auteur_' || auteur);
  liste := liste || jsonb_build_array(jsonb_build_object(
    'id', 'reaction_client', 'le', to_char(jour, 'YYYY-MM-DD'), 'titre', titre, 'heure', null,
    'cree_le', now(), 'par', null, 'systeme', true,
    'reactions', to_jsonb(tous), 'force', force_n, 'extrait', extrait));

  -- 26/10/2026 : l'auteur de la sélection qui ne suit plus le client est tenu au courant
  if auteur is not null and auteur is distinct from suivi then
    liste := liste || jsonb_build_array(jsonb_build_object(
      'id', 'reaction_auteur_' || auteur, 'le', to_char(jour, 'YYYY-MM-DD'),
      'titre', 'Réaction sur ta sélection — ' || array_to_string(parts, ' · ')
               || ' · client suivi par ' || coalesce(suivi, 'personne (pool)'),
      'heure', null, 'cree_le', now(), 'par', auteur, 'conserve', true, 'systeme', true,
      'motif', 'sélection faite par ' || auteur || ', client suivi par ' || coalesce(suivi, 'personne')));
  end if;

  trace := '[' || to_char(jour, 'YYYY-MM-DD') || '] Réaction du client sur sa sélection — ' || array_to_string(trace_parts, ' · ')
        || case when suivi is not null then ' — paternité de ' || suivi || ' relancée pour 14 jours' else '' end;

  perform set_config('glr.interne', '1', true);
  update public.contacts
     set activites = liste,
         notes = case when coalesce(c.notes, '') = '' then trace else c.notes || E'\n' || trace end,
         -- 26/10/2026 : la réaction du client relance la paternité de son vendeur (même échue)
         derniere_action_le = case when suivi is not null then now() else derniere_action_le end,
         paternite_jusqu_au = case when suivi is not null then now() + interval '14 days' else paternite_jusqu_au end
   where id = c.id;
  return new;
exception when others then
  return new;
end $$;

-- 2. Prise dans le pool : note avec l'ancien statut et l'ancien vendeur
create or replace function public.pool_prendre(p_contact uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p text; n int; c public.contacts%rowtype; ancien text; trace text; ancien_statut text;
begin
  perform set_config('glr.interne', '1', true);
  p := public.mon_prenom();
  if p is null then raise exception 'Profil inconnu — impossible de prendre un lead'; end if;
  select count(*) into n from public.pool_prises where vendeur = p and jour = (now() at time zone 'Europe/Paris')::date;
  if n >= public.pool_plafond() then
    raise exception 'Plafond atteint : % leads par jour. Reviens demain.', public.pool_plafond();
  end if;
  select * into c from public.contacts where id = p_contact for update;
  if not found then raise exception 'Contact introuvable'; end if;
  if not exists (select 1 from public.v_pool_leads where id = p_contact) then
    raise exception 'Ce lead n''est plus dans le pool — quelqu''un vient de le prendre';
  end if;
  ancien := nullif(btrim(coalesce(c.vendeur, '')), '');
  ancien_statut := coalesce(nullif(btrim(c.statut), ''), 'Nouveau');
  -- 26/10/2026 : le lead repart en « Nouveau », mais la fiche dit où il en était et qui le suivait
  if (ancien is not null and ancien <> p) or ancien_statut <> 'Nouveau' then
    trace := '[' || to_char(now() at time zone 'Europe/Paris', 'YYYY-MM-DD') || '] Repris du pool par ' || p
          || ' — était en « ' || ancien_statut || ' »'
          || case when ancien is not null and ancien <> p then ', suivi par ' || ancien else '' end;
  end if;
  update public.contacts set
    vendeur = p, vendeur_depuis = now(), paternite_jusqu_au = now() + interval '14 days', paternite_geree = true,
    premiere_action_le = now(), derniere_action_le = now(),
    statut = 'Nouveau', statut_maj = now(),
    rappel_le    = case when ancien = p then rappel_le    else null end,
    rappel_titre = case when ancien = p then rappel_titre else null end,
    rappel_heure = case when ancien = p then rappel_heure else null end,
    veille_depuis = null, veille_motif = null, veille_criteres = null, veille_ecartes = '[]'::jsonb,
    activite_masquee_le = null,
    notes = case when trace is null then notes
                 when nullif(btrim(coalesce(notes, '')), '') is null then trace
                 else notes || E'\n' || trace end,
    vendeur_historique = case
      when ancien is null or ancien = p then coalesce(c.vendeur_historique, '[]'::jsonb)
      else coalesce(c.vendeur_historique, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
             'vendeur', ancien, 'du', c.vendeur_depuis, 'au', now(), 'motif', 'paternité échue — repris dans le pool par ' || p))
    end
  where id = p_contact;
  insert into public.pool_prises (contact_id, vendeur, vendeur_precedent) values (p_contact, p, ancien);
  return jsonb_build_object('ok', true, 'vendeur', p, 'plafond', public.pool_plafond(), 'pris', n + 1, 'restant', public.pool_plafond() - (n + 1));
end $$;

-- 3a. Changement de vendeur : tous les liens actifs du client suivent (avant : seulement ceux de l'ancien vendeur)
create or replace function public.contacts_reattribution_activites() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record; conserve boolean;
begin
  if new.vendeur is null or old.vendeur is null or new.vendeur = old.vendeur then
    return null;
  end if;
  conserve := jsonb_typeof(new.activites) = 'array' and exists (
    select 1 from jsonb_array_elements(new.activites) e
     where e->>'par' = old.vendeur and coalesce((e->>'conserve')::boolean, false));

  for r in
    select * from public.creneaux
     where contact_id = new.id
       and vendeur = old.vendeur
       and statut in ('reserve','propose','confirme')
       and fin > now()
       and not (conserve and coalesce(origine, '') = 'rappel')
  loop
    if coalesce(r.bloquant, true) then
      delete from public.creneaux
       where vendeur = new.vendeur and statut = 'libre'
         and debut < r.fin and fin > r.debut;
    end if;
    update public.creneaux set vendeur = new.vendeur where id = r.id;
  end loop;

  update public.rdv_liens set vendeur = new.vendeur
   where contact_id = new.id and vendeur is distinct from new.vendeur
     and (expires_at is null or expires_at > now());

  update public.selections set vendeur = new.vendeur
   where contact_id = new.id and vendeur = old.vendeur
     and (expires_at is null or expires_at > now());

  return null;
end;
$$;

-- 3b. Compétition tranchée sans changement de vendeur (le premier vendeur agit le
--     premier) : le lien envoyé par l'autre boîte revient au vendeur du client
create or replace function public.contacts_liens_suivent() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if nullif(btrim(coalesce(new.vendeur, '')), '') is null or public.paternite_competition_ouverte(new) then
    return null;
  end if;
  update public.rdv_liens set vendeur = new.vendeur
   where contact_id = new.id and vendeur is distinct from new.vendeur
     and (expires_at is null or expires_at > now());
  return null;
end;
$$;
create trigger trg_contacts_liens_suivent after update of premiere_action_le on public.contacts
  for each row when (old.premiere_action_le is distinct from new.premiere_action_le)
  execute function public.contacts_liens_suivent();

-- 3c. Rattrapage des liens actuels (hors compétition ouverte)
update public.rdv_liens l set vendeur = c.vendeur
  from public.contacts c
 where c.id = l.contact_id and nullif(btrim(coalesce(c.vendeur, '')), '') is not null
   and l.vendeur is distinct from c.vendeur
   and (l.expires_at is null or l.expires_at > now())
   and not public.paternite_competition_ouverte(c);
