-- 26/10/2026 — Un contact « Ne plus contacter » (statut Stop : lien de désinscription
-- des mails, import des désinscrits Brevo, ou choix d'un gérant) ne doit jamais être
-- repris dans le pool. Seul changement : 'Stop' ajouté aux statuts exclus.
-- pool_prendre, pool_recherche et pool_stats lisent tous cette vue : ils suivent.
-- CREATE OR REPLACE garde les droits existants de la vue.

create or replace view public.v_pool_leads as
 SELECT id,
    nom,
    prenom,
    nom_famille,
    nom_confirme,
        CASE
            WHEN est_gerant() THEN email
            ELSE NULL::text
        END AS email,
        CASE
            WHEN est_gerant() THEN telephone
            ELSE NULL::text
        END AS telephone,
        CASE
            WHEN est_gerant() THEN telephone_norm
            ELSE NULL::text
        END AS telephone_norm,
    lieu,
    typologie,
    intention,
    source,
    statut,
    budget,
    budget_min,
    budget_max,
    budget_approx,
        CASE
            WHEN est_gerant() THEN message
            ELSE NULL::text
        END AS message,
    notes,
    reference_annonce,
    prix_annonce,
    date_lead,
    COALESCE(recu_le, created_at) AS cree_le,
    created_at,
    NULLIF(btrim(COALESCE(vendeur, ''::text)), ''::text) AS dernier_vendeur,
    vendeur_depuis,
    derniere_action_le,
    paternite_jusqu_au,
    vendeur_historique,
    ( SELECT count(*) AS count
           FROM pool_prises pp
          WHERE (pp.contact_id = c.id)) AS nb_prises,
        CASE
            WHEN (NULLIF(btrim(COALESCE(vendeur, ''::text)), ''::text) IS NULL) THEN 'jamais_travaille'::text
            ELSE 'echu'::text
        END AS origine
   FROM contacts c
  WHERE ((COALESCE(NULLIF(btrim(statut), ''::text), 'Nouveau'::text) <> ALL (ARRAY['Vendu'::text, 'Perdu'::text, 'Non qualifié'::text, 'En veille'::text, 'Stop'::text])) AND ((NULLIF(btrim(COALESCE(vendeur, ''::text)), ''::text) IS NULL) OR (paternite_echeance(c.*) <= now())));
