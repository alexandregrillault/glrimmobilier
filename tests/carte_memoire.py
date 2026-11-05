# Test de la mémoire de la carte des programmes (05/11/2026) : syntaxe des blocs <script>,
# puis quatre ouvertures avec une base simulée :
#   1. première ouverture      → la carte est téléchargée (pige_carte) et gardée dans le navigateur
#   2. réouverture, même pige  → seule l'étiquette (pige_carte_version) est demandée
#   3. nouvelle pige           → la carte est retéléchargée
#   4. session refusée (401)   → message, carte non affichée, mémoire effacée
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/carte_memoire.py
import json, pathlib, re, subprocess, sys, tempfile
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
CARTE = ICI.parent / 'carte.html'
html = CARTE.read_text(encoding='utf-8')

ok = True
with tempfile.TemporaryDirectory() as d:
    for i, b in enumerate(re.findall(r'<script(?![^>]*src)[^>]*>(.*?)</script>', html, re.S)):
        p = pathlib.Path(d) / f'b{i}.js'; p.write_text(b, encoding='utf-8')
        r = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        if r.returncode: ok = False; print('bloc', i, r.stderr)
print('syntaxe', 'ok' if ok else 'ERREUR')

PROG = {'id': 'p1', 'nom': 'Programme test', 'promoteur': 'Promo', 'ville': 'Clamart', 'cp': '92140', 'dept': '92',
        'lat': 48.8, 'lng': 2.26, 'nb_lots': 1, 'nb_dispo': 1, 'nb_libres': 1, 'prix_min': 250000, 'prix_max': 250000}
LOT = {'id': 'l1', 'programme_id': 'p1', 'n': 'A01', 'type': 'Appartement', 'typo': 'T2', 'pieces': 2, 'surf': 45, 'prix': 250000, 'st': 'libre'}
DATA = {'meta': {'pige_date': '2026-11-04'}, 'genere': '2026-11-04', 'programmes': [PROG], 'lots': [LOT]}

etat = {'version': 'v1', 'statut': 200, 'appels': []}
def base(route):
    nom = route.request.url.rsplit('/', 1)[-1]
    etat['appels'].append(nom)
    if etat['statut'] != 200:
        return route.fulfill(status=etat['statut'], body='{"message":"refusé"}', content_type='application/json')
    corps = json.dumps(etat['version']) if nom == 'pige_carte_version' else json.dumps(DATA)
    route.fulfill(status=200, body=corps, content_type='application/json')

def site(route):
    chemin = route.request.url.split('glr.test/', 1)[1].split('?')[0]
    f = ICI.parent / chemin
    if f.exists(): route.fulfill(status=200, body=f.read_bytes(), content_type='text/html' if chemin.endswith('.html') else 'application/json')
    else: route.fulfill(status=404, body='')

def ouvrir(page):
    etat['appels'].clear()
    page.goto('http://glr.test/carte.html?embed=1')
    page.wait_for_function("!document.getElementById('chargement') || /Impossible/.test(document.getElementById('chargement').innerText)", timeout=20000)
    page.wait_for_timeout(300)
    ov = page.query_selector('#chargement')
    return ov.inner_text() if ov else ''

resultats = []
def verifie(nom, cond): resultats.append(cond); print(('OK   ' if cond else 'ÉCHEC'), nom)

with sync_playwright() as pw:
    nav = pw.chromium.launch()
    ctx = nav.new_context()
    ctx.route('**/glr.test/**', site)
    ctx.route('**/hydqfbxdtpmbuooexekp.supabase.co/rest/v1/rpc/**', base)
    page = ctx.new_page()
    erreurs = []; page.on('pageerror', lambda e: erreurs.append(str(e)))
    page.add_init_script("localStorage.setItem('glr_session', JSON.stringify({access_token: 'jeton-test'}))")

    msg = ouvrir(page)
    verifie('1. première ouverture : carte affichée', msg == '')
    verifie('1. première ouverture : carte téléchargée', 'pige_carte' in etat['appels'])

    msg = ouvrir(page)
    verifie('2. même pige : carte affichée', msg == '')
    verifie('2. même pige : rien retéléchargé', etat['appels'] == ['pige_carte_version'])

    etat['version'] = 'v2'
    msg = ouvrir(page)
    verifie('3. nouvelle pige : carte retéléchargée', 'pige_carte' in etat['appels'] and msg == '')

    etat['statut'] = 401
    msg = ouvrir(page)
    verifie('4. session refusée : carte non affichée', 'Impossible de charger' in msg)
    page.wait_for_timeout(300)
    vide = page.evaluate("""() => new Promise(ok => { const r = indexedDB.open('glr-carte'); r.onupgradeneeded = () => { r.transaction.abort(); ok(true); };
        r.onsuccess = () => { const db = r.result; if (!db.objectStoreNames.contains('donnees')) return ok(true);
          const q = db.transaction('donnees').objectStore('donnees').get('carte'); q.onsuccess = () => ok(!q.result); }; r.onerror = () => ok(true); })""")
    verifie('4. session refusée : mémoire effacée', vide)

    erreurs = [e for e in erreurs if 'Impossible' not in e and 'Session expirée' not in e]
    verifie('aucune erreur JavaScript', not erreurs)
    if erreurs: print(erreurs[:3])
    nav.close()

sys.exit(0 if ok and all(resultats) else 1)
