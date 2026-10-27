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

def lead(lieu, typo, n, ref=None, prix=None, statut='Nouveau', source='SeLoger'):
    return {'reference_annonce': ref, 'prix_annonce': prix, 'date_lead': j(n), 'statut': statut, 'source': source, 'lieu': lieu, 'typologie': typo}
# Leads rangés par ville et typologie : premier lieu de la fiche (celui de l'annonce) et première typologie ;
# à défaut l'intitulé. Les villes et typologies qui suivent sont les critères du client : jamais comptées.
LEADS = [
    *[lead('Clamart (92140)', 'Appartement 2 pièces, T2', i, 'Jules T2 - CLAMART - 45 M²', 237000, 'Suivi' if i % 3 == 0 else 'Sans réponse') for i in (1, 4, 9, 15, 30)],
    lead('Clamart (92140), Meudon 92190', 'Appartement 2 pièces, T3, T4', 33, 'Anaïs', 237000, 'Perdu'),
    *[lead('Colombes (92700)', 'Appartement 2 pièces', i, 'Anaïs', 179000) for i in (2, 3, 10, 20)],
    lead('Colombes (92700)', 'Appartement 2 pièces', 6, None, 181000, source='Leboncoin'),
    lead('Clamart (92140)', 'Appartement 2 pièces', 2, None, 237000, source='Saisie manuelle'),
    lead('Paris 15ème (75015)', 'Appartement 3 pièces, T3', 5, 'Alex T3 - PARIS 15E - 75 M²', 837000, 'Sélections'),
    lead(None, None, 25, 'Jules T2 - SAINT-DENIS PLEYEL - 45 M² - 177 000 €', 177000),
    lead('Saint-Denis (93200)', 'Appartement 2 pièces', 6, 'Théo', 182000),
    lead('Massy (91300)', 'Appartement 4 pièces', 2, 'MTO - T4 - MASSY', 265000),
    lead('Vélizy-Villacoublay (78140)', 'Appartement 3 pièces', 8, 'MTO - VELIZY T3', 347000),
    lead('Rueil-Malmaison (92500)', 'Appartement 3 pièces, T2, T3', 40, 'T3 Rueil-Malmaison Nour', 302000, 'En veille'),
    lead('Annecy (74000)', 'Appartement 5 pièces, T5+', 12, 'Louis T5 - ANNECY - 120 M²', 693000),
    lead(None, None, 3, 'FLP7', 150000),
    lead('Clamart (92140)', None, 3, 'Programme Clamart', None),
    lead("L'Haÿ-les-Roses (94240)", 'Appartement 4 pièces', 70, 'Théo', 337000),
    # Historique : 5 leads T3 à Nanterre il y a 2-3 mois (+ 1 ancien lead RAM, à ignorer)
    *[lead('Nanterre (92000)', 'Appartement 3 pièces', i, 'Jules T3 - NANTERRE - 67 M²', 292500) for i in (75, 78, 80, 85, 88)],
    lead('Nanterre (92000)', None, 82, None, None, source='Ancien lead RAM'),
]
PIGE = [
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.80, 'lng': 2.26, 'prix_min': 295000, 'nb_libres': 13, 'source': 'bouygues'},
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.81, 'lng': 2.27, 'prix_min': 330000, 'nb_libres': 8, 'source': 'lnc'},
    {'ville': 'Clamart', 'cp': '92140', 'lat': 48.81, 'lng': 2.27, 'prix_min': 150000, 'nb_libres': 3, 'source': 'nomandat'},
    {'ville': 'Colombes', 'cp': '92700', 'lat': 48.92, 'lng': 2.25, 'prix_min': 210000, 'nb_libres': 20, 'source': 'nexity'},
    {'ville': 'Paris', 'cp': '75015', 'lat': 48.84, 'lng': 2.30, 'prix_min': 600000, 'nb_libres': 4, 'source': 'cogedim'},
    {'ville': 'Saint-Denis', 'cp': '93200', 'lat': 48.93, 'lng': 2.36, 'prix_min': 199000, 'nb_libres': 31, 'source': 'vinci'},
    {'ville': 'Massy', 'cp': '91300', 'lat': 48.73, 'lng': 2.28, 'prix_min': 240000, 'nb_libres': 0, 'source': 'kaufman'},
    {'ville': 'Nanterre', 'cp': '92000', 'lat': 48.89, 'lng': 2.21, 'prix_min': 290000, 'nb_libres': 8, 'source': 'vinci'},
    {'ville': 'Rueil-Malmaison', 'cp': '92500', 'lat': 48.88, 'lng': 2.19, 'prix_min': 320000, 'nb_libres': 6, 'source': 'ogic'},
]
STOCK = [
    {'cle': 'Clamart', 'ville': 'Clamart', 'cp': '92140', 'type': 'Appartement', 'typo': 'T2', 'nb': 11, 'prix_min': 315000, 'prix_med': 355000, 'surf_min': 35.45, 'programme_min': "Victor's Square (Les Nouveaux Constructeurs)"},
    {'cle': 'Colombes', 'ville': 'Colombes', 'cp': '92700', 'type': 'Appartement', 'typo': 'T2', 'nb': 5, 'prix_min': 170000, 'prix_med': 230000, 'surf_min': 40, 'programme_min': 'Test (Nexity)'},
    {'cle': 'Nanterre', 'ville': 'Nanterre', 'cp': '92000', 'type': 'Appartement', 'typo': 'T3', 'nb': 8, 'prix_min': 290000, 'prix_med': 310000, 'surf_min': 62, 'programme_min': 'Test Nanterre (Vinci)'},
    {'cle': 'Clamart', 'ville': 'Clamart', 'cp': '92140', 'type': 'Appartement', 'typo': 'T3', 'nb': 12, 'prix_min': 360000, 'prix_med': 380000, 'surf_min': 60.31, 'programme_min': 'Opalya (Bouygues Immobilier)'},
    {'cle': 'PARIS 15', 'ville': 'Paris', 'cp': '75015', 'type': 'Appartement', 'typo': 'T3', 'nb': 3, 'prix_min': 1100000, 'prix_med': 1200000, 'surf_min': 70.19, 'programme_min': '15Ème Merveille (Bouygues Immobilier)'},
]
def sl(cle, typo, total, rang, prix, ann, glr=False, releve=None):
    return {'releve': releve or j(1), 'cle': cle, 'typo': typo, 'total': total, 'rang': rang, 'prix': prix, 'surface': 45, 'annonceur': ann, 'promoteur': False, 'glr': glr, 'cree': '2026-09-07', 'sid': f'{cle}{typo}{rang}'}
SELOGER = [sl('Clamart', 'T2', 59, r, 170000 + r * 2000, 'CABINET %d' % r) for r in range(1, 6)] + [
    sl('Clamart', 'T2', 59, 6, 237000, 'GLR IMMOBILIER', True),
    sl('Colombes', 'T2', 40, 1, 150000, 'ELIXIUM'),
    sl('Antony', 'T2', 97, 15, 237000, 'GLR IMMOBILIER', True),
    sl('Massy', 'T4', 0, None, None, None, releve=j(3)),
    *[sl('Clamart', 'T3', 20, r, 280000 + r * 10000, 'CABINET T3 %d' % r) for r in (1, 2, 3)],
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
norm = lambda t: re.sub(r'[\u202f\u00a0]', ' ', t)
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
        page.wait_for_selector('.an-act', timeout=15000)
        page.wait_for_timeout(1500)
        texte = norm(page.text_content('#page-gerant-annonces'))
        for attendu in ('19 leads reçus (SeLoger et Leboncoin) dans 8 villes sur les 60 derniers jours · 1 sans ville lisible',
                        'Saint-Denis · T2', '2 leads · pas de T2 dans la pige', 'Massy · T4', 'Vélizy-Villacoublay · T3', 'Annecy · T5', 'Rueil-Malmaison · T3',
                        'Antony · T2 · 237 000 €', 'en ligne, aucun lead', 'En ligne sur SeLoger (15e sur 97 en prix croissant',
                        'Colombes · T2', 'hors des 120', 'Notre annonce est introuvable dans les 120 premières sur 40',
                        'Nanterre · T3', '5 leads avant · 8 lots', 'Nous avons reçu 5 leads T3 ici', '8 T3 disponibles dès 290 000 €',
                        'Concurrence SeLoger pas encore relevée pour cette ville', 'Clamart · T3', '20 concurrents · 12 lots',
                        'pour être dans les 3 premières il faut moins de 310 000 €', "Comment c'est calculé", 'Leads non rangés (1)', 'FLP7',
                        '4 villes relevées du ' + datetime.date.fromisoformat(j(3)).strftime('%d/%m/%Y') + ' au ' + datetime.date.fromisoformat(j(1)).strftime('%d/%m/%Y')):
            if attendu not in texte: erreurs.append(f'{nom} : « {attendu} » absent')
        for absent in ('Meudon', 'ANCIEN RELEVE', 'Haÿ', 'Clamart · T2'):
            if absent in texte: erreurs.append(f'{nom} : « {absent} » ne devrait pas apparaître')
        if not page.is_visible('#an-faire') or page.is_visible('#an-carte'): erreurs.append(f'{nom} : onglet « À faire » pas affiché par défaut')
        page.screenshot(path=str(SORTIE / f'annonces_{nom}_faire.png'), full_page=False)
        page.evaluate("anOnglet('annonces')"); page.wait_for_timeout(800)
        nb = page.evaluate("document.querySelectorAll('#an-carte .leaflet-interactive').length")
        if nb < 10: erreurs.append(f'{nom} : {nb} ronds sur la carte (nos annonces + offre promoteurs)')
        cl = norm(page.text_content('#an-villes'))
        if 'les villes qui en reçoivent le plus' not in cl or not re.search(r'Clamart\s*7 leads', cl): erreurs.append(f'{nom} : classement « nos annonces » ' + cl[:120])
        page.evaluate("anCouche('ecart')"); page.wait_for_timeout(400)
        cl = norm(page.text_content('#an-villes'))
        if not re.search(r'Clamart\s*SeLoger 32 % moins cher', cl) or 'Colombes' not in cl: erreurs.append(f'{nom} : classement « écart » ' + cl[:160])
        if 'SeLoger 15 % moins cher ou plus' not in page.text_content('#an-legende'): erreurs.append(f'{nom} : légende de l\'écart absente')
        # Fiches des villes : tableau pige / SeLoger / écart / chez nous, puis nos annonces
        fiches = ''
        for k in ('CLAMART', 'COLOMBES', 'MASSY', 'PARIS 15'):
            page.evaluate(f"anVille('{k}')"); page.wait_for_timeout(300)
            fiches += norm(page.text_content('#an-villes')) + ' | '
        for attendu in ('Pige : 2 programmes, 21 lots disponibles, dès 295 000 €', '7 leads reçus sur 60 j', 'Non précisée\n        1 lead', 'Aucun stock dans la pige',
                        '6 leadsdernier ', ', 3 qualifiés', 'annonces à 237 000 €', '11 lotsdès 315 000 €', '59 annoncesdès 172 000 €la nôtre 6e',
                        '-45 %', '-19 %', '-12 %', '5 leadsdernier ', 'annonces à 179 000 € à 181 000 €', '1 leaddernier '):
            if attendu not in fiches: erreurs.append(f'{nom} : fiche ville, « {attendu} » absent')
        page.evaluate("anVille('CLAMART')"); page.wait_for_timeout(300)
        large = page.evaluate('document.documentElement.scrollWidth')
        if large > vp['width'] + 1: erreurs.append(f'{nom} : page plus large que l\'écran ({large} px)')
        page.screenshot(path=str(SORTIE / f'annonces_{nom}.png'), full_page=False)
        if nom == 'bureau':
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
            page.evaluate("anVille(''); anTypo('T3')"); page.wait_for_timeout(300)
            cl = norm(page.text_content('#an-villes'))
            if 'Colombes' in cl or 'SeLoger 19 % moins cher' not in cl: erreurs.append('filtre typologie inopérant : ' + cl[:160])
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
