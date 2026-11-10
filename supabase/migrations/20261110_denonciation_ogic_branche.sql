-- Ogic branché (10/11/2026, « Valide » d'Alex) : premier envoi réel réussi (Botany, Aubervilliers),
-- retrouvé dans « Les dénonciations ». Seuls les clients reçus après ce branchement seront dénoncés.
update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'ogic' and compte = 'ogic';
