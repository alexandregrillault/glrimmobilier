-- Nexity, Catella, Green City (12/11/2026, demande d'Alex : se connecter sans lui chez les promoteurs qui refusent
-- le robot de GitHub). Ces trois sites acceptent le vrai Chrome du Mac : passage horaire sur le Mac
-- (glr-pige/outils/denonciation_mac.sh), jamais sur GitHub (CHROME_MAC dans denonciation_auto.py).
-- Nexity : « Mes prospects » → « Créer un prospect », une fiche par client valable pour toute la France (Alex).
-- Catella : « Déclarer un prospect », une par programme ; leur site refuse la connexion du robot même avec le bon mot
--   de passe : le robot reprend la session ouverte par Alex dans son Chrome, alerte s'il faut se reconnecter.
-- Green City : « Dénoncer un contact », une par programme, objectif d'achat RP, type Appartement.
-- Validés par un vrai envoi avec la fiche de test « Enzo Chopard ». Civilité obligatoire pour Nexity et Green City.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''concilio'', ''pirphi'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''concilio'', ''pirphi'')', '''concilio'', ''pirphi'', ''nexity'', ''greencity'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''concilio'', ''pirphi'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''concilio'', ''pirphi'')', '''concilio'', ''pirphi'', ''nexity'', ''greencity'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('nexity', 'nexity', true, false, true, now(), 'Vrai Chrome du Mac : « Créer un prospect », une fiche par client valable pour toute la France (Alex), civilité obligatoire (12/11/2026)'),
       ('catella', 'catella', false, true, true, now(), 'Vrai Chrome du Mac, session ouverte par Alex (leur site refuse la connexion du robot) : « Déclarer un prospect », une par programme (12/11/2026)'),
       ('greencity', 'greencity', true, true, true, now(), 'Vrai Chrome du Mac : « Dénoncer un contact », une par programme, civilité obligatoire, objectif RP (12/11/2026)')
on conflict do nothing;
