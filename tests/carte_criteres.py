# Test de l'écran de critères de la carte (12/11/2026, demande d'Alex, sur le modèle d'Otaree) :
# les filtres s'ouvrent dans une fenêtre rangée par thèmes (« Critères de recherche »), le compteur
# « lots · programmes » bouge à chaque critère, « Afficher les résultats » referme, et les critères
# actifs restent en pastilles au-dessus de la liste (croix pour en retirer un, « Modifier », « Tout effacer »).
# Lieux (même jour) : un seul champ pour les villes et les départements, plusieurs possibles, rayon en km autour d'une ville.
# Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/carte_criteres.py [dossier des captures]
import json, pathlib, re, subprocess, sys, tempfile
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
CARTE = ICI.parent / 'carte.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI
html = CARTE.read_text(encoding='utf-8')

erreurs = []
with tempfile.TemporaryDirectory() as d:
    for i, b in enumerate(re.findall(r'<script(?![^>]*src)[^>]*>(.*?)</script>', html, re.S)):
        p = pathlib.Path(d) / f'b{i}.js'; p.write_text(b, encoding='utf-8')
        r = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        if r.returncode: erreurs.append(f'syntaxe bloc {i} : {r.stderr[:200]}')

def prog(i, nom, ville, cp, lat, lng):
    return {'id': f't:{i}', 'nom': nom, 'promoteur': 'Promoteur ' + str(i), 'extranet': 'Test', 'ville': ville, 'cp': cp, 'dept': cp[:2],
            'lat': lat, 'lng': lng, 'nb_lots': 2, 'nb_dispo': 2, 'nb_libres': 2, 'prix_min': 300000, 'prix_max': 500000, 'livraison_key': 2028.4, 'commission_pct': 5}
def lot(i, pid, typo, prix, st='libre'):
    return {'id': f't:l{i}', 'programme_id': f't:{pid}', 'n': 'A' + str(i), 'type': 'Appartement', 'typo': typo, 'pieces': int(typo[1]), 'surf': 60, 'prix': prix, 'st': st}
DATA = {'meta': {'pige_date': '2026-11-12', 'prev_date': '2026-11-09', 'nouveaux_programmes': 0, 'nouveaux_lots': 55, 'baisses': 175}, 'genere': '2026-11-12',
        'programmes': [prog(1, 'Les Quais', 'Boulogne-Billancourt', '92100', 48.835, 2.24), prog(2, 'Belvédère', 'Meudon', '92190', 48.81, 2.24), prog(3, 'Atelier', 'Paris', '75018', 48.89, 2.34)],
        'lots': [lot(1, 1, 'T2', 300000), lot(2, 1, 'T3', 450000), lot(3, 2, 'T3', 400000), lot(4, 3, 'T4', 500000, 'option')]}

def base(route):
    nom = route.request.url.rsplit('/', 1)[-1].split('?')[0]
    if '/rpc/' in route.request.url:
        return route.fulfill(status=200, body=json.dumps('v1' if nom == 'pige_carte_version' else DATA), content_type='application/json')
    route.fulfill(status=200, body='[]', content_type='application/json')

def site(route):
    chemin = route.request.url.split('glr.test/', 1)[1].split('?')[0]
    f = ICI.parent / chemin
    if f.exists(): route.fulfill(status=200, body=f.read_bytes(), content_type='text/html' if chemin.endswith('.html') else 'application/json')
    else: route.fulfill(status=404, body='')

with sync_playwright() as pw:
    nav = pw.chromium.launch()
    for nom, vp in (('bureau', {'width': 1280, 'height': 800}), ('iphone', {'width': 390, 'height': 844})):
        ctx = nav.new_context(viewport=vp)
        ctx.route('**/glr.test/**', site)
        ctx.route('**/hydqfbxdtpmbuooexekp.supabase.co/**', base)
        page = ctx.new_page()
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.add_init_script("localStorage.setItem('glr_session', JSON.stringify({access_token: 'jeton-test'}))")
        page.goto('http://glr.test/carte.html?embed=1')
        page.wait_for_function("!document.getElementById('chargement')", timeout=20000)
        page.wait_for_timeout(400)
        def ko(cond, msg):
            if cond: erreurs.append(f'{nom} : {msg}')
        js = page.evaluate
        cache = lambda: js("document.getElementById('crit').hidden")
        compteur = lambda: re.sub(r'\s+', ' ', page.inner_text('#critCount'))

        ko(not cache(), 'la fenêtre des critères est ouverte au chargement')
        # l'en-tête ne doit pas déborder de l'écran (constaté le 12/11/2026 : le nouveau bouton poussait la page de côté)
        if nom == 'bureau': ko(js('document.documentElement.scrollWidth > innerWidth'), 'la page déborde en largeur')
        ko(js("!!document.querySelector('aside select#fPromo, aside #fTypo')"), 'des filtres sont restés dans la colonne')
        ko(js("document.getElementById('active').hidden") is not True, 'pastilles affichées sans critère')

        js("document.getElementById('critBtn').click()")
        page.wait_for_timeout(200)
        ko(cache(), 'la fenêtre ne s’ouvre pas')
        titres = page.eval_on_selector_all('#crit h3', 'els => els.map(e => e.textContent)')
        ko(titres != ['Où', 'Budget', 'Le logement', 'Livraison', 'Pour nous'], f'thèmes {titres}')
        ko(js("document.querySelectorAll('#crit .chip[data-f]').length") != 8, 'pastilles Extérieur / Parking… incomplètes')
        ko(compteur() != '4 lots · 3 programmes', f'compteur de départ {compteur()!r}')
        page.screenshot(path=str(SORTIE / f'carte_criteres_{nom}.png'))

        # un critère : le compteur bouge tout de suite
        js("[...document.querySelectorAll('#fTypo .chip')].find(c => c.firstChild.textContent === 'T3').click()")
        page.wait_for_timeout(200)
        ko(compteur() != '2 lots · 2 programmes', f'compteur après T3 {compteur()!r}')
        page.fill('#fBudget', '420'); page.wait_for_timeout(200)
        ko(compteur() != '1 lot · 1 programme', f'compteur après budget {compteur()!r}')
        js("document.getElementById('critGo').click()")
        page.wait_for_timeout(200)
        ko(not cache(), '« Afficher les résultats » ne referme pas')
        ko(page.inner_text('#critBtn') != 'Critères de recherche (2)', f'bouton {page.inner_text("#critBtn")!r}')
        pastilles = page.eval_on_selector_all('#active .ac', 'els => els.map(e => e.firstChild.textContent)')
        ko(pastilles != ['T3', '≤ 420 k€'], f'pastilles {pastilles}')
        page.screenshot(path=str(SORTIE / f'carte_criteres_pastilles_{nom}.png'))

        # la croix retire un critère sans rouvrir la fenêtre
        js("document.querySelector('#active .ac i').click()"); page.wait_for_timeout(200)
        pastilles = page.eval_on_selector_all('#active .ac', 'els => els.map(e => e.firstChild.textContent)')
        ko(pastilles != ['≤ 420 k€'], f'après la croix {pastilles}')
        ko(js("document.querySelector('#fTypo .chip.on')") is not None, 'T3 encore coché dans la fenêtre')

        # « Modifier » rouvre, Échap referme, « Tout effacer » remet à zéro
        js("document.querySelector('#active .edit').click()"); page.wait_for_timeout(150)
        ko(cache(), '« Modifier » ne rouvre pas la fenêtre')
        page.keyboard.press('Escape'); page.wait_for_timeout(150)
        ko(not cache(), 'Échap ne referme pas')
        js("document.querySelector('#active .all').click()"); page.wait_for_timeout(300)
        ko(js("document.getElementById('active').hidden") is not True, 'pastilles encore là après « Tout effacer »')
        ko(compteur() != '4 lots · 3 programmes', f'compteur après remise à zéro {compteur()!r}')
        ko(page.inner_text('#critBtn') != 'Critères de recherche', 'bouton pas remis à zéro')

        # --- fond de carte : « Plan » par défaut (décision d'Alex du 12/11/2026), « Communes » au choix, gardé sur l'appareil ; lignes en option sur la carte ---
        # « Plan » = carte vectorielle aux couleurs d'Otaree (canvas MapLibre) ; sans WebGL, plan en images (Voyager)
        fondVu = lambda: js("(() => { const c = document.querySelector('.leaflet-tile-pane canvas.maplibregl-canvas'); const i = document.querySelector('.leaflet-tile-pane img'); return c ? 'plan-vectoriel' : (i ? i.src : 'rien'); })()")
        page.wait_for_timeout(1500)
        ko(fondVu() != 'plan-vectoriel' and 'voyager' not in fondVu(), f'fond de départ {fondVu()}')
        ko(js("localStorage.getItem('carteFond')") is not None, 'le fond par défaut ne doit pas être noté comme un choix')
        ko(js("!!document.querySelector('aside #tTransports')") or not js("!!document.querySelector('#mapOpts #tTransports') && !!document.querySelector('#mapOpts #tFutur')"), 'cases des lignes pas sur la carte')
        # en « Plan », aucun contour de commune ni de département
        traits = js("[...document.querySelectorAll('.leaflet-communes-pane path, .leaflet-depts-pane path')].filter(p => +(p.getAttribute('stroke-opacity') || 1) > 0 && p.getAttribute('stroke') !== 'none').length")
        ko(traits != 0, f'{traits} contours encore tracés en « Plan »')
        page.screenshot(path=str(SORTIE / f'carte_fond_plan_{nom}.png'))
        js("document.querySelector('#fondSeg button[data-f=communes]').click()"); page.wait_for_timeout(900)
        ko('light_nolabels' not in fondVu(), f'fond après « Communes » {fondVu()}')
        ko(js("localStorage.getItem('carteFond')") != 'communes', 'choix du fond non gardé')
        js("document.querySelector('#fondSeg button[data-f=plan]').click()"); page.wait_for_timeout(900)
        ko(fondVu() != 'plan-vectoriel' and 'voyager' not in fondVu(), f'retour au fond « Plan » : {fondVu()}')

        # --- lieux : un seul champ, plusieurs villes et départements, rayon autour d'une ville ---
        js("document.getElementById('critBtn').click()"); page.wait_for_timeout(150)
        ko(js("!!document.getElementById('fVillesBtn') || !!document.getElementById('fDeptsBtn')"), 'anciens menus villes / départements encore là')
        page.fill('#lieuQ', 'boul'); page.wait_for_timeout(150)
        prop = page.eval_on_selector_all('#lieuSugg a', 'els => els.map(e => e.innerText.replace(/\\s+/g, " "))')
        ko(not prop or not prop[0].startswith('Boulogne-Billancourt'), f'propositions pour « boul » {prop}')
        page.keyboard.press('Enter'); page.wait_for_timeout(200)
        ko(compteur() != '2 lots · 1 programme', f'Boulogne seule {compteur()!r}')
        # le rayon : Meudon est à environ 3 km du centre de Boulogne
        js("(() => { const c = document.querySelector('#lieuList .lieu[data-t=ville] input[type=range]'); c.value = 2; c.dispatchEvent(new Event('input')); })()"); page.wait_for_timeout(200)
        ko(compteur() != '2 lots · 1 programme', f'Boulogne + 2 km {compteur()!r}')
        js("(() => { const c = document.querySelector('#lieuList .lieu[data-t=ville] input[type=range]'); c.value = 5; c.dispatchEvent(new Event('input')); })()"); page.wait_for_timeout(200)
        ko(compteur() != '3 lots · 2 programmes', f'Boulogne + 5 km {compteur()!r}')
        ko(page.inner_text('#lieuList .lieu .r span') != 'et 5 km autour', 'libellé du rayon')
        # une deuxième ville, puis un département : l'un ou l'autre
        page.fill('#lieuQ', 'paris'); page.wait_for_timeout(150); page.keyboard.press('Enter'); page.wait_for_timeout(200)
        ko(compteur() != '4 lots · 3 programmes', f'Boulogne + 5 km et Paris {compteur()!r}')
        js("document.querySelectorAll('#lieuList .lieu[data-t=ville]')[0].querySelector('button').click()"); page.wait_for_timeout(200)
        ko(compteur() != '1 lot · 1 programme', f'Paris seule {compteur()!r}')
        page.fill('#lieuQ', '92'); page.wait_for_timeout(150)
        prop = page.eval_on_selector_all('#lieuSugg a', 'els => els.map(e => e.innerText.replace(/\\s+/g, " "))')
        ko(not prop or 'Hauts-de-Seine (92)' not in prop[0], f'propositions pour « 92 » {prop}')
        page.keyboard.press('Enter'); page.wait_for_timeout(200)
        ko(compteur() != '4 lots · 3 programmes', f'Paris ou Hauts-de-Seine {compteur()!r}')
        page.screenshot(path=str(SORTIE / f'carte_criteres_lieux_{nom}.png'))
        js("document.getElementById('critGo').click()"); page.wait_for_timeout(150)
        pastilles = page.eval_on_selector_all('#active .ac', 'els => els.map(e => e.firstChild.textContent)')
        ko(pastilles != ['Hauts-de-Seine (92)', 'Paris'], f'pastilles des lieux {pastilles}')
        js("document.querySelector('#active .all').click()"); page.wait_for_timeout(200)
        ko(js("document.querySelectorAll('#lieuList .lieu').length") != 0, 'lieux encore là après « Tout effacer »')
        ctx.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
