-- Ogic (10/11/2026) : une dénonciation par programme (30 jours, 3 programmes au plus en même temps par
-- client), code postal et ville = ville cherchée (comme Bouygues), animateur = le premier proposé pour le
-- programme, civilité facultative (cochée quand on la connaît). Compte créé inactif : branché après un
-- premier envoi réel réussi.
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('ogic', 'ogic', true, true, false, null,
        'Une dénonciation par programme, 30 jours, 3 programmes au plus par client ; ville cherchée + CP (10/11/2026)')
on conflict do nothing;
