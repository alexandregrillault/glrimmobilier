# glrimmobilier — le CRM GLR

Lire d'abord `../CLAUDE.md` (règles communes, routine, préférences d'Alex).

Un CRM maison en un seul fichier `index.html` (vanilla JS, ~1,5 Mo, aucun build), hébergé sur GitHub Pages, authentifié par JWT Supabase. Le dépôt est **public** : toute la sécurité repose sur les policies RLS de la base, jamais sur ce qui est dans le code.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | Le CRM. Tout est dedans : pages, styles, logique. |
| `selection.html` | Copie de secours de la feuille sélection client — identique à `glr-site/selection/index.html`. **Figée** : aucune évolution sans demande explicite d'Alex (décision du 02/10/2026) ; un bug avéré se corrige. |
| `rdv.html` | Copie de secours de la page de rendez-vous client (source : `glr-site/rdv/index.html`). |
| `valider.html` | Confirmation d'un rendez-vous depuis le mail reçu par le vendeur. |
| `mails.html` | Guide des mails automatiques, affiché dans le CRM (Outils → Mails automatiques). À régénérer quand un mail change. |
| `carte.html` + `carte/` | Carte des programmes pigés (iframe dans le CRM). **Ne jamais modifier `carte.html` directement** : il est généré par `pige/current/build_map.py` depuis `map_template.html` (dossier `Desktop/GLR-dashboard/pige/current/` sur le Mac d'Alex). Modifier le template, régénérer, déposer. **Déposer uniquement la version CRM** (`pige/current/crm/carte.html`, ~170 Ko, données lues par la RPC `pige_carte()` avec la session `glr_session`), jamais la version autonome `pige/current/carte.html` (~12 Mo) : elle embarque toute la pige, commissions comprises, et le dépôt est public (règle du 26/10/2026). |
| `simulateur.html` | Simulateur de financement (iframe gérant, ou ouvert avec le contexte d'un client). |
| `programme.html`, `promoteurs.html`, `plaquette.html` | Pages annexes (programme pigé, annuaire promoteurs, plaquette client en diaporama). |
| ~~`rapport-maj.html`~~ | **Retiré le 26/10/2026, ne plus déposer** : le rapport de pige (prix, programmes nommés) était lisible par tous dans ce dépôt public et aucune page n'y renvoyait. Il reste sur le Mac d'Alex (`Desktop/GLR-dashboard/rapport-maj.html`) ; la synthèse est dans la base (`pige_maj.rapport_html`). |
| `gares.json` | Stations ferrées IDF, lu par l'edge function `selection` (lignes de transport à proximité). |

## Deux rôles dans le CRM

- **Gérant** (Alex, Théophile) : accès complet. Pages : Rendez-vous, Chiffres, Contacts, Pilotage, Journal, Documents, Carte, Simulateur, Marché, Annonces.
- **Commercial** (Anaïs, Louis, Nour, Jules, Fabien, Madina) : ses leads, son planning, le pool, ses ventes, les outils. Pas de page Contacts, pas de charges ni de trésorerie, pas de détail des ventes des autres.

Tout nouveau champ de la fiche vendeur utilisé côté commercial doit être ajouté dans la RPC `donnees_espace`.

## Conventions techniques

- Table `ventes` en camelCase → colonnes entre guillemets en SQL (`"vendeurId"`, `"dateActe"`).
- Supabase plafonne chaque réponse REST à 1 000 lignes : utiliser `_sbTout()` pour les grosses lectures (créneaux, événements de pige…).
- Budgets en milliers d'euros (« 300 » = 300 000 €) ; `date_lead` en AAAA-MM-JJ ; commissions au centime.
- Une edge function ne peut pas servir de page HTML : les pages sont des fichiers de ce dépôt, les fonctions ne rendent que du JSON.
- Pas de séquences `\uXXXX` dans le source des edge functions (le déploiement les décode) ; écrire les caractères spéciaux avec `String.fromCharCode`. Après un déploiement, relire le code déployé octet par octet.
- Les policies RLS visent `authenticated`, jamais `anon` (sauf pages publiques).
- Détection de nouvelle version du CRM par ETag : un bandeau « Recharger » apparaît chez les utilisateurs, jamais de rechargement forcé.

## Repères dans index.html

Préfixes : `an*` / `_an*` = page Annonces (registre de nos annonces SeLoger reconstitué depuis `contacts.reference_annonce`, intitulés « Prénom T2 - VILLE - 45 M² » ; `MTO` = Madina, `FLPnn` = Fabien, illisibles ; stock réel = `pige_programmes` hors `picking`/`nomandat`, et par typologie la RPC `annonces_stock()` (lots « libre », `supabase/migrations/20261027_annonces_stock.sql`) ; concurrence = dernier relevé de la table `seloger_concurrence` (gérants seulement), produit par `pige/current/scripts/seloger_concurrence.js` et importé par le bouton « Importer un relevé SeLoger » ; rotation : un tiers des villes à chaque pige (lundi, mercredi, vendredi, lancé par `glr-pige/outils/seloger_concurrence.py`), la page garde pour chaque ville son relevé le plus récent des 10 derniers jours ; SeLoger bloque (CAPTCHA DataDome) au-delà d’une douzaine de villes enchaînées : jamais de contournement), `eq*` = espace équipe (leads, fiche client, planning, rendez-vous), `ct*` = onglet Contacts, `_sel*` = composition d'une sélection, `rdv*` = liens et notifications de rendez-vous, `plaq*` = plaquette, `sim*` = simulateur, `rm*` / `loadMarche` = rapport et page Marché.

Fonctions à connaître : `_eqLeadPatch(id, body)` (toute écriture sur une fiche depuis l'espace équipe), `_eqSelBulk` (actions groupées sur les leads cochés), `eqRdvFixerOuvrir` / `eqRdvFixerValider` / `_rdvFixerProposer` (fixer ou proposer des créneaux depuis la fiche), `eqProposerEnvoyer` (proposer des créneaux depuis le planning), `rdvNotifierClient(token, type, extra)` (tout mail client, via l'edge function `rdv-notif`), `rdvLienRecuperer` (le lien de rendez-vous personnel d'un client), `_planMajSelection` / `_planCalerRappel`, `eqMajVue(force)` (rafraîchissement de la page courante), `renderEquipeLeads` / `renderEquipeLeadsTable`, `toast(message, couleur)`, `_vEsc` (échappement HTML), `nomComplet(l)`, `_creneauVendeur()` (le vendeur dont on regarde l'espace).

Constantes : `RDV_FORMATS` (visio 30 min / appel 10 min), `RDV_FIXE_MAX` (3 créneaux), `STATUTS_LEAD`, `STATUTS_FINAUX`, `SUPABASE_URL`, `SUPABASE_KEY`, `SB_BEARER` (JWT de session), `RDV_SITE_URL`.

## Vérifier avant de commiter

Syntaxe de tous les blocs `<script>` d'un fichier :

```bash
python3 - <<'EOF'
import re, subprocess, sys
s = open('index.html', encoding='utf-8').read()
for i, b in enumerate(re.findall(r'<script(?![^>]*src)[^>]*>(.*?)</script>', s, re.S)):
    open(f'/tmp/blk{i}.js', 'w', encoding='utf-8').write(b)
    r = subprocess.run(['node', '--check', f'/tmp/blk{i}.js'], capture_output=True, text=True)
    print(f'bloc {i}:', 'ok' if r.returncode == 0 else r.stderr)
EOF
```

Test fonctionnel : Playwright (Chromium) sur `file://.../index.html`, en interceptant les appels à `*.supabase.co` pour renvoyer des réponses simulées, en masquant `#login-overlay`, et en appelant directement les fonctions (`_eqLeads = [...]`, `eqRdvFixerOuvrir('id')`…). Vérifier aussi en largeur 390 px (iPhone). Les scripts de test vont dans `tests/` (ex. `tests/annonces.py`, qui contrôle aussi la syntaxe de tous les blocs). Node n'est pas installé sur le Mac d'Alex : lancer les tests avec le Python du robot, `~/glr-pige-robot/.venv/bin/python tests/annonces.py`.

## Règles métier à respecter dans le code

Le détail est dans le document « Règles métier » du projet Cowork. L'essentiel :

- **Paternité** : avoir la paternité = avoir fait la première action commerciale (statut hors Sans réponse, note, qualification, sélection, rendez-vous, conjoint, prise dans le pool, création manuelle). Poser un rappel n'en est pas une. 14 jours, qui repartent à chaque action du vendeur propriétaire ; échéance passée → le lead tombe dans le pool. Réattribution réservée aux gérants (trigger `contacts_protege_attribution`). Celui qui fixe ou propose un rendez-vous depuis la fiche d'un collègue récupère la paternité (RPC `rdv_fixer_paternite`, règle du 03/09/2026). Une réaction du client sur sa sélection (option, intéressé, commentaire…) relance la paternité de son vendeur pour 14 jours, même échue ; si la sélection a été faite par un autre vendeur (`selections.auteur`, figé à la création), celui-ci reçoit une activité conservée pour être tenu au courant (trigger `selection_reaction_client`, règle du 26/10/2026).
- **Pool** : contacts sans vendeur, paternité échue, En veille, Sans réponse ; jamais Vendu, Perdu, Non qualifié, ni « Ne plus contacter » (statut `Stop`, migration `supabase/migrations/20261026_pool_sans_desinscrits.sql`).
- **Ne plus contacter** (`Stop`) : posé par le lien de désinscription des mails (RPC `unsubscribe_contact`, acteur `systeme` au journal), par l'import des désinscrits Brevo ou par un gérant. Jamais visé par une campagne ; l'onglet Contacts ne les montre que si la case est cochée, avec la raison lue dans `journal_audit`. Une campagne groupée ne change aucun statut. 10 prises par jour et par commercial (`pool_plafond`). La prise passe par `pool_prendre(uuid)` : le lead repart en « Nouveau », avec une note « Repris du pool par X — était en « statut », suivi par Y ».
- **Liens de rendez-vous** : les liens actifs d'un client suivent toujours son vendeur (changement de vendeur, ou compétition tranchée), sauf pendant une compétition ouverte (règle du 26/10/2026).
- **Statuts** : Nouveau → Suivi → Sélections → Retour documentation → Finaliser la vente → Vendu ; à côté : Sans réponse, En veille, Perdu, Non qualifié. Tout statut actif impose une date d'activité, sauf En veille. Rien ne reste à vie dans les activités d'un vendeur.
- **Créneaux** : appel 10 min, visio 30 min, base découpée en créneaux de 10 min ; statuts `libre` / `reserve` / `propose` / `confirme` ; contrainte unique (vendeur, debut). Un rendez-vous réservé par le client est « en attente » jusqu'à validation ; une fois sa date passée, la page Activité demande « a-t-il eu lieu ? » (`eqRdvAEuLieu` le compte, `eqRdvPasEuLieu` le retire et le note), sans aucun mail au client. Depuis le 23/10/2026 : de 1 à 3 créneaux depuis la fiche (« Fixer un rendez-vous ») ; 2 ou plus = proposés au client qui confirme ; le planning du vendeur est contrôlé avant toute pose. État du lien `rdv_liens.rdv` : `initiative: 'vendeur'`, `propose_par`, `propose_le` quand c'est le vendeur qui propose.
- **Mails clients** : tous via l'edge function `rdv-notif` (Brevo), au nom du vendeur. Types : `confirme`, `deplace`, `propositions`, `annule`, `libre`, `selection`, `reponse`. Civilité jamais devinée.

## Base (Supabase)

Projet `hydqfbxdtpmbuooexekp`. Le connecteur MCP Supabase sert à lire le schéma, exécuter du SQL et déployer les edge functions.

Edge functions en production : `lead-inbound`, `rdv`, `rdv-notif`, `rdv-alerte`, `rdv-valider`, `selection`, `isochrone`, `site-contact`. Leur source n'est pas encore dans ce dépôt : **avant de modifier une fonction, télécharger la version déployée** (jamais partir d'une copie en mémoire), la déposer dans `supabase/functions/<nom>/index.ts`, modifier, puis déployer et relire. Même logique pour le SQL : chaque migration appliquée devient un fichier `supabase/migrations/AAAAMMJJ_<sujet>.sql` dans ce dépôt (ces dossiers sont à créer à la première occasion).

Attention : l'outil Supabase de Claude n'exécute pas les instructions destructives — l'appel expire après 180 s. Ces instructions sont faites par Alex dans l'éditeur SQL.

## Chantiers connus

- Réattribution groupée (« Réattribuer à… ») : les leads transférés restent affichés tant que la liste n'est pas rechargée, et le compteur final est faux quand des leads sont sautés. À corriger : disparition immédiate du tableau, rechargement jamais ignoré, bilan « transférés / déjà chez X / échecs ».
- Sécurité : table `promoteurs` expose login et mot de passe à tout utilisateur connecté (lecture et modification). À traiter avec l'arbitrage d'Alex.
- Sécurité, pige : lecture publique de `pige_programmes`, `pige_lots`, `pige_archives`, `documents_lot`, `documents_programme` fermée par `supabase/migrations/20261026_pige_lecture_privee.sql` (appliquée le 26/10/2026 ; lecture réservée à `authenticated`). `scripts/immolead_plans.js` lit la liste des lots sans plan par la RPC `lots_sans_plan(source)` (`supabase/migrations/20261026_lots_sans_plan.sql`, appliquée le 26/10/2026). Reste ouverte aux anonymes : l'insertion dans `pige_brut` (push hebdo depuis Chrome).
- Sécurité, documents : dans l'edge function `selection`, les actions `doc_programme`, `doc_lot`, `doc_upload` et `doc_import_url` ne vérifient pas qui appelle : n'importe qui peut remplacer un plan ou une plaquette (visible sur les feuilles sélection client). Utilisées par la carte et par les scripts d'import de documents de la pige. À traiter avec l'arbitrage d'Alex.
- Edge functions et migrations à rapatrier dans ce dépôt (voir « Base »).
