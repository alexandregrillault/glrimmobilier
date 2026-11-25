-- Pages ville : plus aucune manipulation à chaque pige.
--
-- PRÉPARÉE le 25/11/2026, NON APPLIQUÉE. À appliquer APRÈS
-- 20261125_neuf_arrondissements_et_compteurs.sql et 20261125_neuf_communes_ref.sql.
--
-- Demande d'Alex du 25/11/2026 : « A chaque pige il va y avaoir des modifications, comment charger à
-- chaque fois ? », puis « on regarde pour les deux points ». Les deux points :
--   1. les pages du site sont des fichiers : après chaque pige il faut les refabriquer et les pousser ;
--   2. une commune qui reçoit son premier programme n'est pas dans la liste des villes.
--
-- Ce que crée cette migration :
--   A. neuf_villes_completer(p_etat) : ajoute à neuf_villes les communes d'Île-de-France (et les
--      arrondissements de Paris) qui ont un programme à montrer et pas encore de ligne. Une ville de
--      la pige qu'elle ne reconnaît pas est signalée dans la todo d'Alex, jamais devinée.
--   B. neuf_site_lancements : une ligne par pige traitée (lancée ou bloquée).
--   C. neuf_site_lancer(p_force) : après un « publie » de la pige, complète les villes, vérifie les
--      garde-fous, puis demande à GitHub de lancer le robot du site (glr-site, « neuf-publier.yml »),
--      qui refabrique les pages et les met en ligne. Calquée sur robot_lancer().
--   D. la tâche planifiée : toutes les 10 minutes. Sans pige nouvelle elle ne fait rien.
--
-- À TRANCHER PAR ALEX avant d'appliquer (valeurs proposées, marquées « À TRANCHER » plus bas) :
--   - une nouvelle commune part en ligne tout de suite ('publiee') ou attend son oui ('prete') ;
--   - le seuil des garde-fous : pas de lancement si la pige perd plus de 20 % de ses programmes ou
--     de ses logements libres par rapport à la pige d'avant.
-- Tant que la clé GitHub « github_site » n'est pas rangée dans app_secrets par Alex, rien n'est lancé.
-- Aucune donnée existante n'est modifiée ni retirée.

-- A. Compléter la liste des villes -------------------------------------------------------------
create or replace function public.neuf_villes_completer(p_etat text default 'prete')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r           record;
  v_nom       text;
  v_insee     text;
  v_cps       text[];
  v_pv        text[];
  v_slug      text;
  v_arr       integer;
  v_n         integer;
  v_ajoutees  text[] := '{}';
  v_inconnues text[] := '{}';
  v_etape     text;
begin
  if p_etat not in ('prete', 'publiee') then
    raise exception 'etat inconnu : %', p_etat;
  end if;

  for r in
    with lots as (
      select programme_id, count(*) as n
        from pige_lots
       where st in ('libre', 'option') and type in ('Appartement', 'Maison')
         and typo in ('T1', 'T2', 'T3', 'T4', 'T5+')
       group by 1
    )
    select distinct p.dept, p.ville, case when p.dept = '75' then p.cp end as cp
      from pige_programmes p
      left join lots l on l.programme_id = p.id
     where p.dept in ('75', '77', '78', '91', '92', '93', '94', '95')
       and p.ville is not null
       and coalesce(p.source, '') <> 'nomandat'
       and (coalesce(p.source, '') = 'picking' or coalesce(l.n, 0) > 0)
       and not exists (
             select 1 from neuf_villes v
              where v.dept = p.dept
                and p.ville = any(coalesce(v.pige_villes, array[v.ville]))
                and (v.cps is null or p.cp = any(v.cps)))
     order by 1, 2, 3
  loop
    v_nom := null; v_insee := null; v_cps := null; v_pv := null;

    if r.dept = '75' then
      -- Paris : une page par arrondissement, déduit du code postal (75116 = 16e).
      if r.ville = 'Paris' and r.cp ~ '^75(0(0[1-9]|1[0-9]|20)|116)$' then
        v_arr   := case when r.cp = '75116' then 16 else right(r.cp, 2)::int end;
        v_nom   := 'Paris ' || v_arr || case when v_arr = 1 then 'er' else 'e' end;
        v_insee := '751' || lpad(v_arr::text, 2, '0');
        v_cps   := case when v_arr = 16 then array['75016', '75116'] else array[r.cp] end;
        v_pv    := array['Paris'];
      end if;
    else
      select c.insee, r.ville into v_insee, v_nom
        from neuf_communes_ref c
       where c.dept = r.dept and neuf_slug(c.nom) = neuf_slug(r.ville)
       limit 1;
    end if;

    if v_insee is null then
      v_inconnues := v_inconnues || (r.ville || ' (' || coalesce(r.cp, r.dept) || ')');
      continue;
    end if;

    v_slug := neuf_slug(v_nom);
    if exists (select 1 from neuf_villes where slug = v_slug) then
      v_slug := v_slug || '-' || r.dept;
    end if;

    insert into neuf_villes (ville, insee, dept, etat, slug, pige_villes, cps)
    values (v_nom, v_insee, r.dept, p_etat, v_slug, v_pv, v_cps)
    on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      v_ajoutees := v_ajoutees || v_nom;
    end if;
  end loop;

  -- Prévenir Alex dans sa todo (une ligne par lot, pas de doublon tant qu'elle n'est pas cochée).
  if array_length(v_ajoutees, 1) > 0 then
    v_etape := case when p_etat = 'publiee'
                 then 'Nouvelles pages ville mises en ligne après la pige : '
                 else 'Nouvelles communes prêtes pour une page ville, à mettre en ligne : ' end
               || array_to_string(v_ajoutees, ', ');
    insert into gerant_todo (sujet, etape, ordre) values ('Pages ville du site', left(v_etape, 480), 60);
  end if;
  if array_length(v_inconnues, 1) > 0 then
    v_etape := left('Ville de la pige non reconnue, sans page ville : ' || array_to_string(v_inconnues, ', '), 480);
    if not exists (select 1 from gerant_todo where etape = v_etape and fait_le is null) then
      insert into gerant_todo (sujet, etape, ordre) values ('Pages ville du site', v_etape, 61);
    end if;
  end if;

  return jsonb_build_object('ajoutees', to_jsonb(v_ajoutees), 'inconnues', to_jsonb(v_inconnues));
end;
$$;

revoke all on function public.neuf_villes_completer(text) from public, anon, authenticated;
grant execute on function public.neuf_villes_completer(text) to service_role;

-- B. Journal des lancements ----------------------------------------------------------------------
create table if not exists public.neuf_site_lancements (
  pige_id   bigint primary key,          -- pige_maj.id : une ligne par « publie » traité
  pige_date date,
  traite_le timestamptz not null default now(),
  resultat  text not null                -- 'lance', ou 'bloque : …'
);

alter table public.neuf_site_lancements enable row level security;
revoke all on public.neuf_site_lancements from public, anon;
grant select on public.neuf_site_lancements to authenticated;
grant all on public.neuf_site_lancements to service_role;

do $pol$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'neuf_site_lancements' and policyname = 'neuf_site_lancements_lecture') then
    create policy neuf_site_lancements_lecture on public.neuf_site_lancements
      for select to authenticated using (true);
  end if;
end
$pol$;

-- C. Lancer la mise à jour du site après un « publie » -------------------------------------------
-- select public.neuf_site_lancer(true) : relancer à la main la dernière pige, sans garde-fou de chute.
create or replace function public.neuf_site_lancer(p_force boolean default false)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Tranché par Alex le 25/11/2026 (« Oui, toute seule ») : une nouvelle commune part en ligne seule.
  c_etat_nouvelle constant text := 'publiee';
  -- Tranché par Alex le 25/11/2026 (« Oui, 20 % ») : chute tolérée d'une pige à l'autre (0.20 = 20 %).
  c_chute constant numeric := 0.20;
  m      record;
  prec   record;
  cle    text;
  motif  text;
begin
  select id, pige_date, nb_programmes, nb_libres into m
    from pige_maj order by id desc limit 1;
  if m.id is null then
    return 'aucune pige';
  end if;
  if not p_force and exists (select 1 from neuf_site_lancements where pige_id = m.id) then
    return 'rien de neuf';
  end if;

  -- La clé d'abord : sans elle on ne note rien, la tâche réessaiera.
  select value into cle from app_secrets where name = 'github_site';
  if cle is null or cle = '' then
    return 'cle github_site absente de app_secrets';
  end if;

  -- Garde-fous : une pige ancienne ou qui s'effondre n'est jamais mise en ligne toute seule.
  if not p_force then
    select nb_programmes, nb_libres into prec
      from pige_maj where id < m.id order by id desc limit 1;
    if m.pige_date < (now() at time zone 'Europe/Paris')::date - 1 then
      motif := 'pige du ' || to_char(m.pige_date, 'DD/MM') || ' trop ancienne';
    elsif prec.nb_programmes > 0 and m.nb_programmes < prec.nb_programmes * (1 - c_chute) then
      motif := 'programmes en chute : ' || prec.nb_programmes || ' puis ' || m.nb_programmes;
    elsif prec.nb_libres > 0 and m.nb_libres < prec.nb_libres * (1 - c_chute) then
      motif := 'logements libres en chute : ' || prec.nb_libres || ' puis ' || m.nb_libres;
    end if;
    if motif is not null then
      insert into neuf_site_lancements (pige_id, pige_date, resultat)
      values (m.id, m.pige_date, 'bloque : ' || motif)
      on conflict (pige_id) do nothing;
      insert into gerant_todo (sujet, etape, ordre)
      values ('Pages ville du site',
              'Pages ville non mises à jour après la pige du ' || to_char(m.pige_date, 'DD/MM') || ' (' || motif
              || '). Vérifier la pige, puis demander à Claude de relancer.', 62);
      return 'bloque : ' || motif;
    end if;
  end if;

  perform neuf_villes_completer(c_etat_nouvelle);

  perform net.http_post(
    url := 'https://api.github.com/repos/alexandregrillault/glr-site/actions/workflows/neuf-publier.yml/dispatches',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || cle,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'glr-pages-ville',
      'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main'));

  insert into neuf_site_lancements (pige_id, pige_date, resultat)
  values (m.id, m.pige_date, 'lance')
  on conflict (pige_id) do update set traite_le = now(), resultat = 'lance';
  return 'lance';
end;
$$;

revoke all on function public.neuf_site_lancer(boolean) from public, anon, authenticated;
grant execute on function public.neuf_site_lancer(boolean) to service_role;

-- D. Tâche planifiée : toutes les 10 minutes (ne fait rien sans pige nouvelle) --------------------
select cron.schedule('neuf_site_auto', '*/10 * * * *', 'select public.neuf_site_lancer()');
