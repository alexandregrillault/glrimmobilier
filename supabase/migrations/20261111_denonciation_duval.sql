-- Groupe Duval (11/11/2026, autorisation d'Alex de tester, valider et brancher seul) : extranet Leizee,
-- « Dénoncer un prospect » : programme (suggestion « Nom - Ville (78) »), puis fiche contact créée par le
-- « + » (civilité obligatoire, téléphone et mobile, e-mail, provenance « Contact partenaire », permission
-- marketing « Opt-out simple »), puis dénonciation au back-office (valable 45 jours après acceptation).
-- Un client déjà connu de Duval (« associé à un contact existant ») est noté « déjà connu » sans rien valider.
-- Une dénonciation par programme. Branché après des essais remplis correctement (deux clients d'octobre,
-- tous deux déjà connus de Duval) ; aucun envoi réel d'essai, le premier viendra d'un nouveau client.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''saintagne'', ''europeanhomes'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''saintagne'', ''europeanhomes'')', '''saintagne'', ''europeanhomes'', ''duval'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''saintagne'', ''europeanhomes'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''saintagne'', ''europeanhomes'')', '''saintagne'', ''europeanhomes'', ''duval'')');
end
$do$;

insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('duval', 'duval', false, true, true, now(),
        'Une dénonciation par programme : fiche contact (+), puis dénonciation ; civilité obligatoire ; « contact existant » = déjà connu (11/11/2026)')
on conflict do nothing;
