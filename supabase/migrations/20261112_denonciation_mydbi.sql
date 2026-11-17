-- Demathieu Bard (MyDBI), 12/11/2026 : bouton « Dénoncer un contact » trouvé par le robot (demande d'Alex : « tu vas
-- trouver tout seul »). Le site refuse le robot de GitHub : passage horaire dans le vrai Chrome du Mac
-- (CHROME_MAC de glr-pige/robot/denonciation_auto.py). Une dénonciation par programme, valable un mois (dates posées
-- par le site), civilité facultative. Validé par un vrai envoi avec la fiche de test « Enzo Chopard » (PERLE D'ISSY),
-- retrouvé dans le CRM du site en « Nouvelle demande ».
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('mydbi', 'mydbi', true, true, true, now(),
        'Vrai Chrome du Mac : « Dénoncer un contact », une par programme, valable un mois, civilité facultative (12/11/2026)')
on conflict do nothing;
