-- Ogic exige la civilité (11/11/2026 : « Indiquez la civilité » sur un client sans civilité connue ; on la
-- croyait facultative le 10/11). Ogic rejoint la liste des plateformes où la civilité est obligatoire :
-- sans civilité confirmée ni déduite du prénom, pas d'Ogic, et le carré rouge de la fiche la demande.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('''europeanhomes'', ''duval'')' in d) = 0 then raise exception 'liste introuvable (a_faire)'; end if;
  execute replace(d, '''europeanhomes'', ''duval'')', '''europeanhomes'', ''duval'', ''ogic'')');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('''europeanhomes'', ''duval'')' in d) = 0 then raise exception 'liste introuvable (manques)'; end if;
  execute replace(d, '''europeanhomes'', ''duval'')', '''europeanhomes'', ''duval'', ''ogic'')');
end
$do$;
