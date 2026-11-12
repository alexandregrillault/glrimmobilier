# Test du parrainage dans le CRM (décisions d'Alex du 12/11/2026) : page Parrainage de
# l'Espace Gérant (cartes à envoyer, filleuls en cours, cartes envoyées, pastille) et bloc
# « Parrainage » de la fiche client (parrain, ajout d'un parrain, lien du client). Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/parrainage.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

PARRAINS = [
    {'id': 'p1', 'code': 'ABC234', 'prenom': 'Marie', 'nom': 'Durand', 'email': 'marie@ex.fr', 'telephone': '0611111111', 'contact_id': None, 'origine': 'site', 'cree_le': '2026-11-10T10:00:00Z', 'cree_par': None},
    {'id': 'p2', 'code': 'XYZ789', 'prenom': 'Karim', 'nom': 'Benali', 'email': 'karim@ex.fr', 'telephone': None, 'contact_id': 'c2', 'origine': 'crm', 'cree_le': '2026-11-11T10:00:00Z', 'cree_par': 'Alex'},
]
SUIVI = [
    {'filleul_id': 'c1', 'filleul_nom': 'Paul Martin', 'filleul_statut': 'Vendu', 'filleul_vendeur': 'theophile', 'filleul_recu_le': '2026-09-01T10:00:00Z',
     'parrain_id': 'p1', 'parrain_code': 'ABC234', 'parrain_nom': 'Marie Durand', 'parrain_email': 'marie@ex.fr', 'parrain_telephone': '0611111111',
     'vente_programme': 'Scène 3', 'vente_lot': 'A12', 'signe_le': '2026-11-05', 'signe': True, 'carte_parrain_le': None, 'carte_filleul_le': '2026-11-08T10:00:00Z'},
    {'filleul_id': 'c3', 'filleul_nom': 'Léa Petit', 'filleul_statut': 'Suivi', 'filleul_vendeur': 'louis', 'filleul_recu_le': '2026-11-11T10:00:00Z',
     'parrain_id': 'p2', 'parrain_code': 'XYZ789', 'parrain_nom': 'Karim Benali', 'parrain_email': 'karim@ex.fr', 'parrain_telephone': None,
     'vente_programme': None, 'vente_lot': None, 'signe_le': None, 'signe': False, 'carte_parrain_le': None, 'carte_filleul_le': None},
]
CARTES = [{'id': 'k1', 'filleul_id': 'c1', 'beneficiaire': 'filleul', 'parrain_id': 'p1', 'montant': 500, 'note': None, 'envoyee_le': '2026-11-08T10:00:00Z', 'envoyee_par': 'Alex'}]
LEADS = [
    {'id': 'c1', 'nom': 'Paul Martin', 'prenom': 'Paul', 'nom_famille': 'Martin', 'email': 'paul@ex.fr', 'telephone': '0612345678', 'statut': 'Vendu', 'vendeur': 'theophile', 'parrain_id': 'p1', 'notes': '', 'activites': [], 'appels': []},
    {'id': 'c2', 'nom': 'Karim Benali', 'prenom': 'Karim', 'nom_famille': 'Benali', 'email': 'karim@ex.fr', 'telephone': '0622222222', 'statut': 'Suivi', 'vendeur': 'theophile', 'parrain_id': None, 'notes': '', 'activites': [], 'appels': []},
    {'id': 'c4', 'nom': 'Sophie Roux', 'prenom': 'Sophie', 'nom_famille': 'Roux', 'email': 'sophie@ex.fr', 'telephone': '0633333333', 'statut': 'Nouveau', 'vendeur': 'theophile', 'parrain_id': None, 'notes': '', 'activites': [], 'appels': []},
]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        parrains = json.loads(json.dumps(PARRAINS)); cartes = json.loads(json.dumps(CARTES)); suivi = json.loads(json.dumps(SUIVI))
        envois, patchs, crees, suppr = [], [], [], []
        def repond(r):
            u, m = r.request.url, r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rpc/parrainage_suivi' in u:
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(suivi))
            if '/rest/v1/parrainage_cartes' in u and m == 'POST':
                o = json.loads(r.request.post_data); envois.append(o)
                for s in suivi:
                    if s['filleul_id'] == o['filleul_id']: s['carte_' + o['beneficiaire'] + '_le'] = '2026-11-12T10:00:00Z'
                cartes.insert(0, dict(o, id='k%d' % (len(cartes) + 1), envoyee_le='2026-11-12T10:00:00Z', envoyee_par='Alex'))
                return r.fulfill(status=201, body='')
            if '/rest/v1/parrainage_cartes' in u and m == 'DELETE':
                suppr.append(u.split('id=eq.')[1]); return r.fulfill(status=204, body='')
            if '/rest/v1/parrainage_cartes' in u:
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(cartes))
            if '/rest/v1/parrains' in u and m == 'POST':
                o = json.loads(r.request.post_data); crees.append(o)
                n = dict(o, id='p%d' % (len(parrains) + 1), code='NEW%03d' % len(crees), cree_le='2026-11-12T10:00:00Z', cree_par='Alex')
                parrains.insert(0, n)
                return r.fulfill(status=201, content_type='application/json', body=json.dumps([n]))
            if '/rest/v1/parrains' in u:
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(parrains))
            if '/rest/v1/contacts' in u and m == 'PATCH':
                patchs.append((u.split('id=eq.')[1], json.loads(r.request.post_data))); return r.fulfill(status=204, body='')
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("() => { _hideLogin(); MON_ROLE = { prenom: 'Alex', role: 'gerant' }; }")

        # ---- Page gérant
        page.evaluate("goTo('gerant-parrainage', null)")
        page.wait_for_timeout(600)
        t = page.inner_text('#parr-page').replace('\u202f', ' ').replace('\xa0', ' ')
        for attendu in ('1 000 €', 'Marie Durand, parrain de', 'Paul Martin', 'Scène 3', 'Léa Petit', 'Karim Benali', '500 € à Paul Martin'):
            if attendu not in t: erreurs.append(f'{nom} : page sans « {attendu} »')
        if page.locator('#parr-page button', has_text='Carte envoyée').count() != 1:
            erreurs.append(f'{nom} : il faut une seule carte à envoyer (celle du parrain)')
        if page.inner_text('#nav-parr-pastille') != '1': erreurs.append(f'{nom} : pastille {page.inner_text("#nav-parr-pastille")!r}')
        page.screenshot(path=str(SORTIE / f'parrainage_gerant_{nom}.png'), full_page=True)
        page.locator('#parr-page button', has_text='Carte envoyée').click()
        page.wait_for_timeout(600)
        if envois != [{'filleul_id': 'c1', 'beneficiaire': 'parrain', 'parrain_id': 'p1', 'montant': 1000}]:
            erreurs.append(f'{nom} : envoi inattendu {envois}')
        if page.locator('#parr-page button', has_text='Carte envoyée').count() != 0: erreurs.append(f'{nom} : carte toujours à envoyer')
        if page.inner_text('#nav-parr-pastille') not in ('', '0'): erreurs.append(f'{nom} : pastille après envoi')
        page.on('dialog', lambda d: d.accept())
        page.locator('#parr-page button', has_text='Annuler').first.click()
        page.wait_for_timeout(400)
        if not suppr: erreurs.append(f'{nom} : « Annuler » n’a rien supprimé')

        # ---- Fiche client
        page.evaluate("(l) => { _eqLeads = l; }", LEADS)
        page.evaluate("eqOuvrirFiche('c1')"); page.wait_for_timeout(500)
        f = page.inner_text('#eq-fiche-corps')
        if 'Recommandé par Marie Durand' not in f: erreurs.append(f'{nom} : fiche c1 sans son parrain')
        if 'Créer son lien de parrainage' not in f: erreurs.append(f'{nom} : fiche c1 sans « Créer son lien »')
        page.screenshot(path=str(SORTIE / f'parrainage_fiche_{nom}.png'))
        page.evaluate("eqOuvrirFiche('c2')"); page.wait_for_timeout(400)
        f = page.inner_text('#eq-fiche-corps')
        if 'parrainage/?p=XYZ789' not in f: erreurs.append(f'{nom} : fiche c2 sans son lien de parrainage')
        # Ajouter un parrain nouveau sur c4
        page.evaluate("eqOuvrirFiche('c4')"); page.wait_for_timeout(400)
        page.locator('#eq-fiche-corps button', has_text='Ajouter un parrain').click()
        page.fill('#parr-prenom-c4', 'Hugo'); page.fill('#parr-tel-c4', '0644444444')
        page.screenshot(path=str(SORTIE / f'parrainage_ajout_{nom}.png'))
        page.locator('#eq-fiche-corps button', has_text='Enregistrer').click(); page.wait_for_timeout(600)
        if not crees or crees[-1].get('prenom') != 'Hugo' or crees[-1].get('origine') != 'crm': erreurs.append(f'{nom} : parrain non créé {crees}')
        if not patchs or patchs[-1][0] != 'c4' or not patchs[-1][1].get('parrain_id'): erreurs.append(f'{nom} : fiche non rattachée {patchs}')
        if 'Recommandé par Hugo' not in page.inner_text('#eq-fiche-corps'): erreurs.append(f'{nom} : parrain ajouté non affiché')
        # Choisir un parrain existant sur c2 ? Non : un client ne peut pas être son propre parrain
        page.evaluate("eqOuvrirFiche('c2')"); page.wait_for_timeout(300)
        page.locator('#eq-fiche-corps button', has_text='Ajouter un parrain').click()
        opts = page.eval_on_selector_all('#parr-choix-c2 option', 'o => o.map(x => x.textContent)')
        if any('Karim' in o for o in opts): erreurs.append(f'{nom} : le client est proposé comme son propre parrain')

        if nom == 'iphone':
            larg = page.evaluate('document.documentElement.scrollWidth')
            if larg > 392: erreurs.append(f'iphone : la page déborde ({larg}px)')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Parrainage CRM : tout est bon')
sys.exit(1 if erreurs else 0)
