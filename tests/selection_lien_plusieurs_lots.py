# Un lien Otaree avec plusieurs lots du même programme (demande d'Alex du 16/11/2026) :
# la fonction « selection » (action extraire) rend tous les lots dans « lots » ; le
# dashboard doit les ajouter tous, chacun avec son lien propre, rangés sous un seul programme.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/selection_lien_plusieurs_lots.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI
LIEN = 'https://glr-immobilier.otaree.com/v/02beb05f8ce7'

def lot(num, prix, plan):
    return {'ok': True, 'titre': f'Terre de Sens - Lot {num}', 'lien': LIEN + '#lot-' + num, 'programme': 'TERRE DE SENS',
            'ville': 'Gennevilliers 92230', 'promoteur': 'Catella', 'prix': prix, 'typologies': ['T3'], 'surface': '71,90 m²',
            'plan': plan, 'plans': [plan], 'masse': 'https://x/masse.jpg', 'plaquette': 'https://x/plaquette.pdf', 'images': [], 'transports': []}
LOTS = [lot('C103', '404 000 €', 'https://x/c103.jpg'), lot('D003', '389 000 €', 'https://x/d003.jpg'), lot('B403', '421 000 €', 'https://x/b403.jpg')]
REPONSE_MULTI = {**LOTS[0], 'lots': LOTS}
REPONSE_UN = {**lot('A12', '300 000 €', 'https://x/a12.jpg'), 'lien': 'https://glr-immobilier.otaree.com/v/aaaaaa111111', 'titre': 'Autre - Lot A12', 'programme': 'AUTRE'}

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e, nom=nom: erreurs.append(f'{nom} : {e}'))
        def route(r, *_):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if r.request.method == 'POST' and '/functions/v1/selection' in r.request.url:
                corps = json.loads(r.request.post_data or '{}')
                if corps.get('action') == 'extraire':
                    rep = REPONSE_MULTI if '02beb05f8ce7' in corps.get('lien', '') else REPONSE_UN
                    return r.fulfill(status=200, content_type='application/json', body=json.dumps(rep))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        page.evaluate("""() => { _hideLogin();
            const d = document.createElement('div'); d.id = 'bloc-test';
            d.style.cssText = 'position:fixed;inset:0;z-index:1500;background:#fff;padding:16px;overflow:auto';
            d.innerHTML = '<textarea id="sel-otaree-liens"></textarea><button id="sel-otaree-btn">Analyser les liens</button><div id="sel-libres"></div>';
            document.body.appendChild(d);
            _selCtx = { lead: { id: 'c1', nom: 'Test' }, libres: [] }; }""")
        page.fill('#sel-otaree-liens', LIEN + '\nhttps://glr-immobilier.otaree.com/v/aaaaaa111111')
        page.evaluate("selExtraireLiens()")
        page.wait_for_function("document.getElementById('sel-otaree-btn').textContent === 'Analyser les liens' && _selCtx.libres.length > 0", timeout=15000)
        r = page.evaluate("_selCtx.libres.map(b => [b.titre, b.lien, b.plan])")
        titres = [x[0] for x in r]
        for n in ('C103', 'D003', 'B403', 'A12'):
            if not any(n in t for t in titres): erreurs.append(f'{nom} : lot {n} absent : {titres}')
        if len(r) != 4: erreurs.append(f'{nom} : {len(r)} lots au lieu de 4')
        if len({x[1] for x in r}) != 4: erreurs.append(f'{nom} : deux lots partagent le même lien : {r}')
        if not any(x[0].endswith('C103') and x[2].endswith('c103.jpg') for x in r): erreurs.append(f'{nom} : C103 n\'a pas son plan')
        t = page.inner_text('#sel-libres')
        if t.count('TERRE DE SENS') + t.count('Terre de Sens') < 1 or '3 lots' not in t:
            erreurs.append(f'{nom} : les 3 lots ne sont pas rangés sous un même programme : {t[:400]}')
        page.screenshot(path=str(SORTIE / f'lien_plusieurs_lots_{nom}.png'))
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
