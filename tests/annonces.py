# Test de la page Annonces (gérants) : syntaxe de tous les blocs <script>,
# rendu bureau et iPhone avec des réponses Supabase simulées.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/annonces.py
import json, pathlib, re, sys, datetime
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def j(n):
    return (datetime.date.today() - datetime.timedelta(days=n)).isoformat()

LEADS = [
    *[{'reference_annonce': 'Jules T2 - CLAMART - 45 M²', 'prix_annonce': 237000, 'date_lead': j(i), 'statut': 'Suivi' if i % 3 == 0 else 'Sans réponse'} for i in (1, 4, 9, 15, 30)],
    {'reference_annonce': 'Jules T2 - CLAMART - 45 M² - 237 000 €', 'prix_annonce': 237000, 'date_lead': j(33), 'statut': 'Perdu'},
    *[{'reference_annonce': 'Anaïs T2 - COLOMBES - 44 M²', 'prix_annonce': 179000, 'date_lead': j(i), 'statut': 'Nouveau'} for i in (2, 3, 10, 20)],
    {'reference_annonce': 'Alex T3 - PARIS 15E - 75 M²', 'prix_annonce': 837000, 'date_lead': j(5), 'statut': 'Sélections'},
    {'reference_annonce': 'Jules T2 - SAINT-DENIS PLEYEL - 45 M² - 177 000 €', 'prix_annonce': 177000, 'date_lead': j(25), 'statut': 'Sans réponse'},
    {'reference_annonce': 'Jules T2 - SAINT-DENIS - 45 M²', 'prix_annonce': 182000, 'date_lead': j(6), 'statut': 'Sans réponse'},
    {'reference_annonce': 'MTO - T4 - MASSY', 'prix_annonce': 265000, 'date_lead': j(2), 'statut': 'Nouveau'},
    {'reference_annonce': 'MTO - VELIZY T3', 'prix_annonce': 347000, 'date_lead': j(8), 'statut': 'Nouveau'},
    {'reference_annonce': 'T3 Rueil-Malmaison Nour', 'prix_annonce': 302000, 'date_lead': j(40), 'statut': 'En veille'},
    {'reference_annonce': 'Louis T5 - ANNECY - 120 M²', 'prix_annonce': 693000, 'date_lead': j(12), 'statut': 'Nouveau'},
    {'reference_annonce': 'FLP7', 'prix_annonce': 150000, 'date_lead': j(3), 'statut': 'Nouveau'},
    {'reference_annonce': 'Anaïs', 'prix_annonce': 161000, 'date_lead': j(50), 'statut': 'Nouveau'},
    {'reference_annonce': 'Théo T4 - L HAY-LES-ROSES - 84 M²', 'prix_annonce': 337000, 'date_lead': j(70), 'statut': 'Nouveau'},
    # Demande sans annonce : deux leads qui cherchent un T3 à Nanterre
    {'reference_annonce': None, 'prix_annonce': None, 'date_lead': j(4), 'statut': 'Nouveau', 'lieu': 'Nanterre 92000, Puteaux 92800', 'typologie': 'Appartement 3 pièces'},
    {'reference_annonce': '', 'prix_annonce': None, 'date_lead': j(9), 'statut': 'Nouveau', 'lieu': 'Nanterre (92000)', 'typologie': 'T3'},
    {'reference_annonce': None, 'prix_annonce': None, 'date_lead': j(11), 'statut': 'Nouveau', 'lieu': 'Nanterre 92000', 'typologie': '3 pièces'},
]
PIGE = [
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.80, 'lng': 2.26, 'prix_min': 295000, 'nb_libres': 13, 'source': 'bouygues'},
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.81, 'lng': 2.27, 'prix_min': 330000, 'nb_libres': 8, 'source': 'lnc'},
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.81, 'lng': 2.27, 'prix_min': 150000, 'nb_libres': 3, 'source': 'nomandat'},
    {'ville': 'Colombes', 'cp': '92700', 'lat': 48.92, 'lng': 2.25, 'prix_min': 210000, 'nb_libres': 20, 'source': 'nexity'},
    {'ville': 'Paris', 'cp': '75015', 'lat': 48.84, 'lng': 2.30, 'prix_min': 600000, 'nb_libres': 4, 'source': 'cogedim'},
    {'ville': 'Saint-Denis', 'cp': '93200', 'lat': 48.93, 'lng': 2.36, 'prix_min': 199000, 'nb_libres': 31, 'source': 'vinci'},
    {'ville': 'Massy', 'cp': '91300', 'lat': 48.73, 'lng': 2.28, 'prix_min': 240000, 'nb_libres': 0, 'source': 'kaufman'},
    {'ville': 'Rueil-Malmaison', 'cp': '92500', 'lat': 48.88, 'lng': 2.19, 'prix_min': 320000, 'nb_libres': 6, 'source': 'ogic'},
]
STOCK = [
    {'cle': 'Clamart', 'ville': 'Clamart', 'cp': '92140', 'type': 'Appartement', 'typo': 'T2', 'nb': 11, 'prix_min': 315000, 'prix_med': 355000, 'surf_min': 35.45, 'programme_min': "Victor's Square (Les Nouveaux Constructeurs)"},
    {'cle': 'Colombes', 'ville': 'Colombes', 'cp': '92700', 'type': 'Appartement', 'typo': 'T2', 'nb': 5, 'prix_min': 170000, 'prix_med': 230000, 'surf_min': 40, 'programme_min': 'Test (Nexity)'},
    {'cle': 'Nanterre', 'ville': 'Nanterre', 'cp': '92000', 'type': 'Appartement', 'typo': 'T3', 'nb': 8, 'prix_min': 290000, 'prix_med': 310000, 'surf_min': 62, 'programme_min': 'Test Nanterre (Vinci)'},
    {'cle': 'PARIS 15', 'ville': 'Paris', 'cp': '75015', 'type': 'Appartement', 'typo': 'T3', 'nb': 3, 'prix_min': 1100000, 'prix_med': 1200000, 'surf_min': 70.19, 'programme_min': '15Ème Merveille (Bouygues Immobilier)'},
]
def sl(cle, typo, total, rang, prix, ann, glr=False, releve=None):
    return {'releve': releve or j(1), 'cle': cle, 'typo': typo, 'total': total, 'rang': rang, 'prix': prix, 'surface': 45, 'annonceur': ann, 'promoteur': False, 'glr': glr, 'cree': '2026-09-07', 'sid': f'{cle}{typo}{rang}'}
SELOGER = [sl('Clamart', 'T2', 59, r, 170000 + r * 2000, 'CABINET %d' % r) for r in range(1, 6)] + [
    sl('Clamart', 'T2', 59, 6, 237000, 'GLR IMMOBILIER', True),
    sl('Colombes', 'T2', 40, 1, 150000, 'ELIXIUM'),
    sl('Antony', 'T2', 97, 15, 237000, 'GLR IMMOBILIER', True),
    sl('Massy', 'T4', 0, None, None, None, releve=j(3)),
    sl('Clamart', 'T2', 80, 1, 99000, 'ANCIEN RELEVE', releve=j(3)),
]
GEO = {'VELIZY': {'nom': 'Vélizy-Villacoublay', 'centre': {'coordinates': [2.19, 48.78]}, 'codeDepartement': '78'},
       'ANNECY': {'nom': 'Annecy', 'centre': {'coordinates': [6.13, 45.90]}, 'codeDepartement': '74'}}

APPELS = []
def route(r):
    u = r.request.url
    if 'seloger_concurrence' in u and r.request.method in ('POST', 'DELETE'):
        APPELS.append((r.request.method, u, r.request.post_data))
    if 'supabase.co' in u:
        if '/rest/v1/contacts' in u: body = LEADS
        elif '/rest/v1/pige_programmes' in u: body = PIGE
        elif '/rest/v1/rpc/annonces_stock' in u: body = STOCK
        elif '/rest/v1/seloger_concurrence' in u: body = SELOGER
        else: body = []
        return r.fulfill(status=200, content_type='application/json', body=json.dumps(body))
    if 'geo.api.gouv.fr' in u:
        nom = re.search(r'nom=([^&]+)', u).group(1)
        c = GEO.get(nom.replace('%20', ' ').split(' ')[0])
        return r.fulfill(status=200, content_type='application/json', body=json.dumps([c] if c else []))
    return r.continue_()

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp)
        page.on('pageerror', lambda e: erreurs.append(str(e)))
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            # Syntaxe : chaque bloc <script> compilé par le moteur du navigateur
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
        page.evaluate("""() => { _hideLogin();
            try { localStorage.removeItem('glr-an-geo'); } catch (e) {} goTo('gerant-annonces', null); }""")
        page.wait_for_selector('.an-ville', timeout=15000)
        page.wait_for_timeout(1500)
        texte = re.sub(r'[\u202f\u00a0]', ' ', page.inner_text('#page-gerant-annonces'))
        for attendu in ('Clamart', '6 leads', 'Saint-Denis', 'Pige : 2 programmes, 21 lots disponibles, dès 295 000 €',
                        'Aucun stock dans la pige', 'FLP7', 'Madina', 'Vélizy-Villacoublay', 'Paris 15e',
                        'Pige : 11 T2 dispo, dès 315 000 € (35 m²)', 'annonce -25 %', 'annonce +5 %', 'annonce -24 %',
                        'Aucun T4 disponible dans la pige', 'aucun lot de cette typologie dans la ville',
                        'notre annonce 6e sur 59 en prix croissant', 'la moins chère 172 000 € (CABINET 1)', 'top 5 sous 180 000 €',
                        'introuvable dans les 120 premières (40 annonces)', 'aucune annonce T4 neuve dans la ville',
                        '4 villes relevées du ' + datetime.date.fromisoformat(j(3)).strftime('%d/%m/%Y') + ' au ' + datetime.date.fromisoformat(j(1)).strftime('%d/%m/%Y'), 'Aucun T2 disponible dans la pige à Saint-Denis', 'En ligne sur SeLoger (15e sur 97 en prix croissant', 'Antony · T2 45 m² · 237 000 €',
                        'Introuvable dans les 120 premières sur 40', 'Nanterre · T3', '3 leads cherchaient un T3 dans cette ville sur la période', '8 T3 disponibles dès 290 000 €',
                        'Concurrence SeLoger pas encore relevée pour cette ville', 'Règles utilisées'):
            if attendu not in texte: erreurs.append(f'{nom} : « {attendu} » absent')
        if 'Rueil-Malmaison · T3 · 302 000 € — Nour' in texte: erreurs.append(f'{nom} : ancien intitulé proposé au retrait')
        if 'ANCIEN RELEVE' in texte: erreurs.append(f'{nom} : ancien relevé de Clamart affiché')
        if 'Théo' in texte: erreurs.append(f'{nom} : lead de plus de 60 jours compté')
        nb = page.evaluate("document.querySelectorAll('#an-carte .leaflet-interactive').length")
        if nb < 6: erreurs.append(f'{nom} : {nb} ronds sur la carte')
        large = page.evaluate('document.documentElement.scrollWidth')
        if large > vp['width'] + 1: erreurs.append(f'{nom} : page plus large que l\'écran ({large} px)')
        page.screenshot(path=str(SORTIE / f'annonces_{nom}.png'), full_page=False)
        if nom == 'bureau':
            page.evaluate("anVille('CLAMART')")
            if page.locator('.an-ville').count() != 1: erreurs.append('filtre ville inopérant')
            # Import d'un fichier de relevé : suppression des seules villes du fichier, puis insertion
            f = SORTIE / 'releve_test.json'
            f.write_text(json.dumps({'source': 'seloger.com', 'releve': '2026-10-28', 'villes': 2, 'complet': False,
                'lignes': [sl("L'Haÿ-les-Roses", 'T2', 3, 1, 200000, 'X'), sl('Clamart', 'T3', 0, None, None, None)]}))
            page.set_input_files('#an-fichier', str(f))
            page.wait_for_timeout(1500)
            meth = [a[0] for a in APPELS]
            if meth != ['DELETE', 'POST']: erreurs.append(f'import : appels {meth}')
            elif 'releve=eq.2026-10-28' not in APPELS[0][1] or 'Clamart' not in APPELS[0][1] or 'Ha%C3%BF' not in APPELS[0][1]: erreurs.append('import : suppression mal ciblée ' + APPELS[0][1])
            elif len(json.loads(APPELS[1][2])) != 2 or json.loads(APPELS[1][2])[0]['releve'] != '2026-10-28': erreurs.append('import : insertion incorrecte')
            f.unlink()
            page.evaluate("anVille(''); anVendeur('Jules')")
            if 'Colombes' in page.inner_text('#an-villes'): erreurs.append('filtre vendeur inopérant')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
