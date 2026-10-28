# Test de l'onglet « Robot SeLoger » de la page Annonces (gérants) : syntaxe de tous les blocs <script>,
# rendu bureau et iPhone avec des passages du robot simulés (table seloger_recreation_passages).
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/annonces_robot.py
import json, pathlib, re, sys, datetime
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI
AUJ = datetime.date.today()

def passage(n, recrees, prevu, arret=None, detail=None):
    jour = (AUJ - datetime.timedelta(days=n)).isoformat()
    return {'id': 100 - n, 'jour': jour, 'debut': jour + 'T08:13:00+00:00', 'fin': jour + 'T09:02:00+00:00', 'prevu': prevu,
            'recrees': recrees, 'supprimees': recrees, 'en_ligne': 313, 'arret': arret,
            'resume': [f'{recrees} annonce(s) recréée(s) sur {prevu} prévue(s).', 'Par vendeur : Théo 6, MTO 4.', 'Par typologie : T3 5, T4 3, T2 2.',
                       'Prix : 5 baissé(s) de 2 000 €, 5 remonté(s) de 2 000 €.', 'Photos : 10,4 en moyenne, 1 annonce(s) sous 9 photos (note sous 70).'],
            'detail': detail or []}

PASSAGES = [
    passage(0, 10, 10, detail=[{'ville': 'Créteil', 'ref': 'Théo T4 - CRETEIL - 84 M²', 'prix_avant': 291997, 'prix': 289997, 'photos': 12, 'etat': 'en cours de publication'}]),
    passage(1, 4, 10, arret='SeLoger demande une vérification anti-robot'),
    passage(2, 10, 10),
]

def route(r):
    u = r.request.url
    if 'supabase.co' in u:
        body = PASSAGES if '/rest/v1/seloger_recreation_passages' in u else []
        return r.fulfill(status=200, content_type='application/json', body=json.dumps(body))
    return r.continue_()

erreurs = []
norm = lambda t: re.sub(r'[  ]', ' ', t)
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp)
        page.on('pageerror', lambda e: erreurs.append(str(e)))
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("() => { _hideLogin(); goTo('gerant-annonces', null); }")
        page.wait_for_timeout(1500)
        page.evaluate("anOnglet('robot')")
        page.wait_for_selector('.an-robot-tete', timeout=10000)
        page.wait_for_timeout(500)
        texte = norm(page.text_content('#an-robot'))
        for attendu in ("Fait aujourd'hui", '10 annonces recréées sur 10', 'recréées sur 14 jours', '313', 'Par vendeur : Théo 6, MTO 4.',
                        'Arrêt', 'SeLoger demande une vérification anti-robot', 'Détail des 1 annonce(s)', '291 997 € → 289 997 €'):
            if attendu not in texte: erreurs.append(f'{nom} : « {attendu} » absent')
        if not re.search(r'\b24\s*recréées sur 14 jours', texte): erreurs.append(f'{nom} : total sur 14 jours faux')
        if page.is_visible('#an-faire') or page.is_visible('#an-carte'): erreurs.append(f'{nom} : les autres onglets restent visibles')
        large = page.evaluate('document.documentElement.scrollWidth > window.innerWidth + 1')
        if large: erreurs.append(f'{nom} : la page déborde en largeur')
        page.screenshot(path=str(SORTIE / f'annonces_robot_{nom}.png'), full_page=False)
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Onglet Robot SeLoger : tout est bon')
sys.exit(1 if erreurs else 0)
