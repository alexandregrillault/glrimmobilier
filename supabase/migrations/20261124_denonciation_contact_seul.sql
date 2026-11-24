-- Dénonciations : « contact créé, à dénoncer » (constat d'Alex du 24/11/2026 sur Linea Rosa, Primavefa).
-- Chez Link-app (Primavefa, NACA, Infineo, GBI), le robot crée seulement la fiche du contact ; la
-- dénonciation est une deuxième étape, programme par programme, qu'il ne fait pas encore. Ces lignes
-- étaient affichées en vert (« envoyé et retrouvé ») : 135 lignes, 87 clients.
-- Décision d'Alex : tant que le robot ne fait pas la deuxième étape, orange « Contact créé · à dénoncer ».
--
-- Troisième niveau de preuve : 'contact' = la fiche du client existe chez le promoteur, rien de plus.
-- Le statut reste 'envoyee' (le robot ne recrée pas la fiche, et un mail « dénonciation acceptée » du
-- promoteur passe toujours la ligne en 'acceptee', donc en vert).
-- denonciation_comptes.contact_seul : comptes où le robot ne fait que créer le contact ; toute nouvelle
-- ligne 'envoyee' de ces comptes naît au niveau 'contact'. À remettre à false compte par compte quand le
-- robot saura dénoncer sur le programme.

create table public.denonciations_backup_20261124 as select * from public.denonciations;
alter table public.denonciations_backup_20261124 enable row level security;

alter table public.denonciations drop constraint denonciations_preuve_niveau_check;
alter table public.denonciations add constraint denonciations_preuve_niveau_check
  check (preuve_niveau = any (array['liste'::text, 'message'::text, 'contact'::text]));

alter table public.denonciation_comptes add column contact_seul boolean not null default false;
update public.denonciation_comptes set contact_seul = true where plateforme = 'linkapp';

create or replace function public.denonciations_completer()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_par boolean; v_jours integer; v_contact boolean;
begin
  select dc.par_programme, dc.paternite_jours, dc.contact_seul into v_par, v_jours, v_contact
  from public.denonciation_comptes dc where dc.compte = new.compte limit 1;
  if new.portee is null then
    -- comptes « contact seul » : la dénonciation se fera programme par programme, une ligne ne vaut que pour le sien
    new.portee := case when v_par is false and not coalesce(v_contact, false) then 'client' else 'programme' end;
  end if;
  if v_contact and new.statut = 'envoyee' then
    new.preuve_niveau := 'contact';  -- fiche créée chez le promoteur, pas encore dénoncée sur le programme
  end if;
  if new.preuve_niveau is null then
    new.preuve_niveau := public.denonciation_preuve_niveau(new.statut, new.detail);
  end if;
  if new.paternite_fin is null and v_jours is not null and new.statut in ('envoyee', 'acceptee') then
    new.paternite_fin := (coalesce(new.fait_le, now()) at time zone 'Europe/Paris')::date + v_jours;
  end if;
  return new;
end $function$;

update public.denonciations set preuve_niveau = 'contact'
 where plateforme = 'linkapp' and statut = 'envoyee';

-- Link-app dénonce programme par programme : une ligne (contact créé, ou acceptée par mail sur un programme)
-- ne vaut plus pour les autres programmes du même promoteur.
update public.denonciations set portee = 'programme' where plateforme = 'linkapp' and portee = 'client';
