-- Ymmea branché (10/11/2026, autorisation d'Alex de tester, valider et brancher seul) : premier envoi réel
-- réussi (Le Perreux-sur-Marne), « Dénonciation acceptée et protégée pour 60 jours ». Budget et typologie
-- obligatoires : sans eux pas de Ymmea, et le carré rouge de la fiche demande le budget.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.robot_denonciations_a_faire_plateformes(text,integer)'::regprocedure);
  if position('  order by x.compte, x.recu_le' in d) = 0 then raise exception 'ancre introuvable (a_faire)'; end if;
  execute replace(d, '  order by x.compte, x.recu_le',
    '    and (x.plateforme <> ''ymmea''
         or (coalesce(nullif(c.budget_max, 0), nullif(c.budget_min, 0), nullif(c.prix_annonce, 0)) is not null
             and public.denonciation_typologie(c.typologie) is not null))
  order by x.compte, x.recu_le');
  d := pg_get_functiondef('public.denonciation_manques(uuid)'::regprocedure);
  if position('count(*) filter (where plateforme = ''station9'')' in d) = 0 then raise exception 'ancre introuvable (manques)'; end if;
  execute replace(d, 'count(*) filter (where plateforme = ''station9'')', 'count(*) filter (where plateforme in (''station9'', ''ymmea''))');
end
$do$;

update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'ymmea' and compte = 'ymmea';
