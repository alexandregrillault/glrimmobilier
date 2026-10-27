# Test de la page Marché : vue 5 jours, boutons « Vidéo du dimanche » / « Bonus » et bandeau
# « Vidéos Quoi de neuf » (table qdn_videos simulée), bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/marche_videos.py
import json, pathlib, re, sys, datetime, uuid
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

AUJ = datetime.date.today()
def j(n): return (AUJ - datetime.timedelta(days=n)).isoformat()
# Même règle que _qdnLundis() : semaine = lundi du premier focus (épisode la veille, le dimanche).
LUNDI = AUJ - datetime.timedelta(days=AUJ.weekday()) + datetime.timedelta(days=7 if AUJ.weekday() == 6 else 0)
PROCHAIN = LUNDI + datetime.timedelta(days=7)
BONUS = PROCHAIN if AUJ.weekday() in (4, 5) else LUNDI
MOIS = AUJ.replace(day=1).isoformat()
MOIS_PREV = (AUJ.replace(day=1) - datetime.timedelta(days=1)).replace(day=1).isoformat()

def prog(i, nom, ville, dept, libres, lk=2028.2):
    return {'id': i, 'nom': nom, 'ville': ville, 'dept': dept, 'promoteur': 'Promo ' + nom, 'livraison': 'T2 2028', 'lk': lk, 'source': 'x',
            'fisc': ['PTZ'], 'url': None, 'gare': 'RER B', 'gare_dist': 400, 'libres': libres, 'prix_min': 250000, 'pm2': 6000,
            'typos': 'T1 T2 T3', 'stock0': libres, 'vendus': 0, 'baisses': 0, 'revenus': 0}
PROGS = [prog('k:103', 'Le 103', 'Malakoff', '92', 14), prog('b:martre', 'Carré Martre', 'Clichy', '92', 38),
         prog('n:arpents', 'Les Quarante Arpents', 'Alfortville', '94', 10), prog('w:unisson', 'Unisson', 'Wissous', '91', 0, 2026.1),
         prog('c:vieux', 'Vieux Lancement', 'Melun', '77', 20)]
def lanc(i, kind, date, nom, ville, mois=MOIS):
    return {'id': i, 'kind': kind, 'mois': mois, 'date': date, 'nom': nom, 'ville': ville, 'promoteur': 'Promo ' + nom}
LANC = [lanc('k:103', 'extranet', j(22), 'Le 103', 'Malakoff'),              # ouvert à la prescription il y a 22 j, revu par la dernière pige
        lanc('b:martre', 'nouveau', j(1), 'Carré Martre', 'Clichy'),
        lanc('n:arpents', 'nouveau', j(1), 'Les Quarante Arpents', 'Alfortville'),
        lanc('w:unisson', 'nouveau', j(1), 'Unisson', 'Wissous'),            # livré, sans stock : pas de bouton
        lanc('c:vieux', 'nouveau', j(15), 'Vieux Lancement', 'Melun')]       # hors de la fenêtre de 5 jours
def marche(jours):
    deb = j(4) if jours <= 7 else j(30)
    return {'meta': {'fin': j(1), 'debut': deb, 'jours': 3, 'mois': MOIS, 'mois_prev': MOIS_PREV, 'nb_piges': 2, 'nb_programmes': 5, 'nb_libres': 82, 'vendus': 3},
            'villes': [{'ville': p['ville'], 'dept': p['dept'], 'progs': 1, 'libres': p['libres'], 'stock0': 20, 'vendus': 1, 'pm2': 6000, 'prix_min': 250000, 'pct': 5} for p in PROGS],
            'programmes': PROGS, 'lancements': LANC}
EVENEMENTS = [{'programme_id': 'k:103', 'pige_date': j(1)}]

VIDEOS = [  # cette semaine : épisode déjà fait, 2 focus
    {'id': str(uuid.uuid4()), 'programme_id': 'x:a', 'nom': 'Scène 3', 'ville': 'Le Plessis-Robinson', 'promoteur': 'Emerige', 'type': 'lundi', 'semaine': LUNDI.isoformat(), 'ordre': 1, 'statut': 'postee'},
    {'id': str(uuid.uuid4()), 'programme_id': 'x:b', 'nom': 'Hameau du Lac', 'ville': 'Noisy', 'promoteur': 'X', 'type': 'lundi', 'semaine': LUNDI.isoformat(), 'ordre': 2, 'statut': 'a_faire'},
]
DEPART = [dict(v) for v in VIDEOS]
APPELS = []
def route(r):
    u, m = r.request.url, r.request.method
    if 'supabase.co' not in u: return r.continue_()
    q = parse_qs(urlparse(u).query)
    if '/rpc/marche_donnees' in u:
        body = marche(json.loads(r.request.post_data)['p_jours'])
    elif '/rest/v1/pige_evenements' in u:
        body = EVENEMENTS
    elif '/rest/v1/qdn_videos' in u:
        APPELS.append(m)
        idf = q.get('id', [''])[0].replace('eq.', '')
        if m == 'POST':
            v = json.loads(r.request.post_data); v.update({'id': str(uuid.uuid4()), 'statut': 'a_faire'}); VIDEOS.append(v); body = [v]
        elif m == 'DELETE':
            VIDEOS[:] = [v for v in VIDEOS if v['id'] != idf]; body = []
        elif m == 'PATCH':
            for v in VIDEOS:
                if v['id'] == idf: v.update(json.loads(r.request.post_data))
            body = []
        else:
            body = sorted(VIDEOS, key=lambda v: (v['semaine'], v['type'], v['ordre']))
    else:
        body = []
    return r.fulfill(status=200, content_type='application/json', body=json.dumps(body))

erreurs = []
norm = lambda t: re.sub(r'[  ]', ' ', t)
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        VIDEOS[:] = [dict(v) for v in DEPART]   # chaque largeur repart de la même base
        page = nav.new_page(viewport=vp)
        page.on('pageerror', lambda e: erreurs.append(str(e)))
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("() => { _hideLogin(); goTo('marche', null); }")
        page.wait_for_selector('.mk-card', timeout=15000)
        page.evaluate("mkPeriode(5)"); page.wait_for_timeout(1200)
        t = norm(page.text_content('#page-marche'))
        for attendu in ('Vidéos Quoi de neuf', 'Cette semaine', 'Épisode récap : Scène 3, Hameau du Lac', 'Focus Scène 3', 'Postée', 'Focus Hameau du Lac',
                        'Aucun programme choisi', 'Le 103', 'Carré Martre', 'Les Quarante Arpents', 'Pas de vidéo : livré ou sans logement libre'):
            if attendu not in t: erreurs.append(f'{nom} : « {attendu} » absent')
        if 'Vieux Lancement' in t: erreurs.append(f'{nom} : un lancement hors fenêtre de 5 jours est affiché')
        if nom == 'bureau':
            # Le 103 : date de la dernière pige, pas celle du rapport
            c103 = norm(page.locator('.mk-card', has_text='Le 103').text_content())
            if 'vu le ' + datetime.date.fromisoformat(j(1)).strftime('%-d') not in c103: erreurs.append('Le 103 : date récente absente : ' + c103[:80])
            # Trois programmes pour lundi, dans l'ordre des clics, puis un bonus
            for n in ('Le 103', 'Carré Martre', 'Les Quarante Arpents'):
                page.locator('.mk-card', has_text=n).get_by_role('button', name='Vidéo du dimanche').click(); page.wait_for_timeout(500)
            page.locator('.mk-card', has_text='Carré Martre').get_by_role('button', name='Bonus').click(); page.wait_for_timeout(500)
            lun = sorted([v for v in VIDEOS if v['semaine'] == PROCHAIN.isoformat()], key=lambda v: v['ordre'])
            if [v['nom'] for v in lun] != ['Le 103', 'Carré Martre', 'Les Quarante Arpents'] or [v['ordre'] for v in lun] != [1, 2, 3]:
                erreurs.append('sélection du lundi : ' + str([(v['nom'], v['ordre']) for v in lun]))
            bon = [v for v in VIDEOS if v['type'] == 'bonus']
            if len(bon) != 1 or bon[0]['semaine'] != BONUS.isoformat(): erreurs.append('bonus : ' + str(bon))
            t = norm(page.text_content('#page-marche'))
            for attendu in ('1. lundi', '2. mardi', '3. mercredi', 'Bonus Carré Martre', 'Jeudi', 'Épisode du dimanche'):
                if attendu not in t: erreurs.append(f'après choix : « {attendu} » absent')
            # Monter Les Quarante Arpents en 2e, puis changer l'état d'un focus, puis décocher
            page.locator('.qdn-l', has_text='Les Quarante Arpents').get_by_role('button', name='Monter').click(); page.wait_for_timeout(600)
            lun = sorted([v for v in VIDEOS if v['semaine'] == PROCHAIN.isoformat()], key=lambda v: v['ordre'])
            if [v['nom'] for v in lun] != ['Le 103', 'Les Quarante Arpents', 'Carré Martre']: erreurs.append('Monter : ' + str([v['nom'] for v in lun]))
            page.locator('.qdn-l', has_text='Focus Hameau du Lac').get_by_role('button', name='À faire').click(); page.wait_for_timeout(500)
            if next(v for v in VIDEOS if v['nom'] == 'Hameau du Lac')['statut'] != 'faite': erreurs.append('état du focus non changé')
            page.locator('.mk-card', has_text='Le 103').get_by_role('button', name='✓ Vidéo du dimanche').click(); page.wait_for_timeout(500)
            if any(v['nom'] == 'Le 103' for v in VIDEOS): erreurs.append('décocher Le 103 ne le retire pas')
            if 'à choisir pour avoir un focus' not in norm(page.text_content('#page-marche')): erreurs.append('alerte « à choisir » absente')
            # Retour à 30 jours : vue par mois, le vieux lancement revient
            page.evaluate("mkPeriode(30)"); page.wait_for_timeout(1000)
            if 'Vieux Lancement' not in norm(page.text_content('#page-marche')): erreurs.append('vue 30 jours : lancement du mois absent')
            page.evaluate("mkPeriode(5)"); page.wait_for_timeout(1000)
        large = page.evaluate('document.documentElement.scrollWidth')
        if large > vp['width'] + 1: erreurs.append(f'{nom} : page plus large que l\'écran ({large} px)')
        page.screenshot(path=str(SORTIE / f'marche_videos_{nom}.png'), full_page=False)
        page.locator('.mk-grid').first.scroll_into_view_if_needed()
        page.screenshot(path=str(SORTIE / f'marche_videos_{nom}_cartes.png'), full_page=False)
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
