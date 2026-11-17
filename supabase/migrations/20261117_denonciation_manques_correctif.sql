-- Correctif du 17/11/2026 (contrôle des dénonciations demandé par Alex) : `manque := manque || 'nom'` faisait
-- planter denonciation_manques (« malformed array literal » : 'nom' lu comme un tableau). Le carré rouge
-- « Dénonciations en attente » ne s'affichait donc jamais sur une fiche sans nom de famille ou sans civilité.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('manque := manque || ''nom''' in d) = 0 then raise exception 'ligne introuvable'; end if;
  d := replace(d, 'manque := manque || ''nom''', 'manque := array_append(manque, ''nom'')');
  d := replace(d, 'manque := manque || ''civilite''', 'manque := array_append(manque, ''civilite'')');
  d := replace(d, 'manque := manque || ''budget''', 'manque := array_append(manque, ''budget'')');
  execute d;
end
$do$;
