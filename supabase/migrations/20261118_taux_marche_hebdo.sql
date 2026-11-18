-- Mise à jour hebdomadaire du taux des simulations (baromètre Meilleurtaux),
-- demandée par Alex le 18/11/2026 : le cache simulateur_taux_marche ne se
-- rafraîchissait jusqu'ici que quand quelqu'un ouvrait une simulation.
-- Chaque mercredi à 7 h UTC (8 h à Paris en hiver, 9 h en été).
-- Appliquée le 18/11/2026.
select cron.schedule(
  'taux_marche_hebdo',
  '0 7 * * 3',
  $$select net.http_get(url := 'https://hydqfbxdtpmbuooexekp.supabase.co/functions/v1/taux-marche?force=1', timeout_milliseconds := 30000)$$
);
