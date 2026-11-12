# Test des lots à plusieurs plans sur la carte (12/11/2026, demande d'Alex : duplex Ateliers Dollfus
# 601/602, « 601 haut » + « 601 bas », dont un seul s'affichait) : syntaxe, liens « Plan 1 » / « Plan 2 »
# dans la fiche du programme et dans la vue « Lots », plan unique inchangé, plans transmis à la sélection.
# Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/carte_plans_multiples.py [dossier des captures]
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

PROG = {'id': 'catella:1128', 'nom': 'Ateliers Dollfus', 'promoteur': 'Pierre Promotion', 'ville': 'Paris', 'cp': '75018', 'dept': '75',
        'lat': 48.898, 'lng': 2.34, 'nb_lots': 3, 'nb_dispo': 3, 'nb_libres': 3, 'prix_min': 400000, 'prix_max': 1221000}
U = 'https://api.catellapatrimoine.fr/uploads/'
LOTS = [
    {'id': 'catella:23867', 'programme_id': 'catella:1128', 'n': '601', 'type': 'Appartement', 'typo': 'T5+', 'pieces': 5, 'surf': 132.12, 'prix': 1221000, 'st': 'libre',
     'plan': U + 'haut601.pdf', 'plans': [U + 'haut601.pdf', U + 'bas601.pdf']},
    {'id': 'catella:23866', 'programme_id': 'catella:1128', 'n': '406', 'type': 'Appartement', 'typo': 'T5+', 'pieces': 5, 'surf': 120, 'prix': 1100000, 'st': 'libre',
     'plan': U + 'bas406.pdf', 'plans': [U + 'bas406.pdf', U + 'mi406.pdf', U + 'haut406.pdf']},
    {'id': 'catella:1', 'programme_id': 'catella:1128', 'n': '101', 'type': 'Appartement', 'typo': 'T2', 'pieces': 2, 'surf': 45, 'prix': 400000, 'st': 'libre',
     'plan': U + 'seul101.pdf'},
]
DATA = {'meta': {'pige_date': '2026-11-12'}, 'genere': '2026-11-12', 'programmes': [PROG], 'lots': LOTS}

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
    for nom, vp in (('bureau', {'width': 1400, 'height': 900}), ('iphone', {'width': 390, 'height': 844})):
        ctx = nav.new_context(viewport=vp)
        ctx.route('**/glr.test/**', site)
        ctx.route('**/hydqfbxdtpmbuooexekp.supabase.co/**', base)
        ctx.route('**/api.catellapatrimoine.fr/**', lambda r: r.fulfill(status=200, body='%PDF-1.4', content_type='application/pdf'))
        page = ctx.new_page()
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.add_init_script("localStorage.setItem('glr_session', JSON.stringify({access_token: 'jeton-test'}))")
        page.goto('http://glr.test/carte.html?embed=1')
        page.wait_for_function("!document.getElementById('chargement')", timeout=20000)
        page.wait_for_timeout(400)

        # Fiche du programme, ouverte par la recherche comme un commercial
        page.fill('#q', 'Dollfus')
        page.wait_for_timeout(300)
        page.press('#q', 'ArrowDown')
        page.press('#q', 'Enter')
        page.wait_for_timeout(600)
        liens = page.eval_on_selector_all('#lotsTbl a.plan-a', 'els => els.map(e => e.textContent + "=" + e.getAttribute("href").split("/").pop())')
        attendu = ['Plan 1=haut601.pdf', 'Plan 2=bas601.pdf', 'Plan 1=bas406.pdf', 'Plan 2=mi406.pdf', 'Plan 3=haut406.pdf', 'PDF=seul101.pdf']
        if sorted(liens) != sorted(attendu): erreurs.append(f'{nom} : liens de la fiche {liens}')
        page.screenshot(path=str(SORTIE / f'carte_plans_{nom}.png'))
        # Ouverture du 2e plan dans l'aperçu
        # clic par la page : sur iPhone la carte déborde déjà de l'écran (constaté avant ce changement)
        page.eval_on_selector('#lotsTbl a.plan-a[href$="bas601.pdf"]', 'a => a.click()')
        page.wait_for_timeout(300)
        titre = page.inner_text('#docModalTitre')
        if titre != 'Plan — lot 601 — plan 2/2': erreurs.append(f'{nom} : titre de l’aperçu {titre!r}')
        if not page.evaluate("document.getElementById('docModal').classList.contains('on')"): erreurs.append(f'{nom} : aperçu non ouvert')
        page.eval_on_selector('#docModalFermer', 'b => b.click()')

        # Vue « Lots »
        page.eval_on_selector('#tabs span[data-t="l"]', 't => t.click()')
        page.wait_for_timeout(400)
        liens = page.eval_on_selector_all('a.plan-a', "els => els.filter(e => !e.closest('#lotsTbl')).map(e => e.textContent)")
        if liens.count('Plan 1') != 2 or liens.count('Plan 3') != 1 or liens.count('Plan') != 1: erreurs.append(f'{nom} : vue Lots {liens}')
        page.screenshot(path=str(SORTIE / f'carte_plans_lots_{nom}.png'))
        ctx.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
