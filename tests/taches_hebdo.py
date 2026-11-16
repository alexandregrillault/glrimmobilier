# Test des tâches hebdomadaires des gérants (demande d'Alex du 16/11/2026) : les 7 jours,
# le jour courant mis en avant, cocher / décocher une tâche (enregistrée dans gerant_hebdo
# pour la semaine en cours), tâche du mois rangée au 1er du mois, filtre « À faire
# seulement », pastille du menu = tâches du jour restantes. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/taches_hebdo.py [dossier des captures]
import datetime, json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

auj = datetime.date.today()
LUNDI = (auj - datetime.timedelta(days=auj.weekday())).isoformat()
PREMIER = auj.replace(day=1).isoformat()
JOUR = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'][auj.weekday()]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1500, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        # Déjà en base : le robot SeLoger du jour, coché par Théophile ; une ligne décochée
        lignes = [{'semaine': LUNDI, 'cle': JOUR + '-seloger', 'fait': True, 'maj_par': 'Théophile', 'maj_le': '2026-11-16T10:00:00Z'},
                  {'semaine': LUNDI, 'cle': 'ven-bilan', 'fait': False, 'maj_par': 'Alex', 'maj_le': '2026-11-16T10:00:00Z'}]
        envois = []
        def repond(r):
            u, m = r.request.url, r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rest/v1/gerant_hebdo' in u and m == 'POST':
                o = json.loads(r.request.post_data); envois.append(o)
                l = dict(o, maj_par='Alex', maj_le='2026-11-16T11:00:00Z')
                lignes[:] = [x for x in lignes if not (x['semaine'] == o['semaine'] and x['cle'] == o['cle'])] + [l]
                return r.fulfill(status=201, content_type='application/json', body=json.dumps([l]))
            if '/rest/v1/gerant_hebdo' in u:
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(lignes))
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if not x.endswith(': ok')]

        page.evaluate("() => { _hideLogin(); MON_ROLE = { prenom: 'Alex', role: 'gerant' }; }")
        page.evaluate("goTo('gerant-hebdo', null)")
        page.wait_for_timeout(400)
        if page.inner_text('#topbar-title') != 'Tâches hebdomadaires': erreurs.append(f'{nom} : titre {page.inner_text("#topbar-title")!r}')
        if page.locator('.hb-jour').count() != 7: erreurs.append(f'{nom} : il faut 7 jours')
        if page.locator('.hb-jour.hb-auj').count() != 1: erreurs.append(f'{nom} : jour courant non mis en avant')
        lundi = page.inner_text('#hb-jour-0')
        for attendu in ('Vidéo 1', 'Pige : écrire', 'Robot SeLoger : 35', '6 h 17'):
            if attendu not in lundi: erreurs.append(f'{nom} : lundi sans « {attendu} »')
        # ordre : le robot de 6 h avant la tâche « pige » de 9 h 30, avant les tâches sans heure
        if not (lundi.index('6 h') < lundi.index('Pige : écrire') < lundi.index('Vidéo 1')): erreurs.append(f'{nom} : ordre du lundi')
        if 'Vidéo 2' not in page.inner_text('#hb-jour-2') or 'Vidéo 3' not in page.inner_text('#hb-jour-4'): erreurs.append(f'{nom} : vidéos 2 et 3')
        if 'Focus' in page.inner_text('#hb-jours') or 'LinkedIn' in page.inner_text('#hb-jours'): erreurs.append(f'{nom} : il reste des vidéos retirées')
        # coche existante (Théophile) et ligne décochée
        auj_txt = page.inner_text('#hb-jour-%d' % auj.weekday())
        if 'Théophile' not in auj_txt: erreurs.append(f'{nom} : coche de Théophile non affichée')
        if page.locator('#hb-jour-%d .hb-fait' % auj.weekday()).count() != 1: erreurs.append(f'{nom} : coche du jour non relue')
        if page.locator('#hb-jour-4 .hb-fait').count() != (1 if JOUR == 'ven' else 0): erreurs.append(f'{nom} : ligne décochée lue comme faite')
        attendu = page.locator('#hb-jour-%d .hb-toi' % auj.weekday()).count() - 1
        past = page.inner_text('#nav-hebdo-pastille') if attendu else ''
        if past != (str(attendu) if attendu else ''): erreurs.append(f'{nom} : pastille {past!r} au lieu de {attendu}')
        page.screenshot(path=str(SORTIE / f'taches_hebdo_{nom}.png'), full_page=(nom == 'bureau'))

        # Cocher la vidéo du mercredi
        page.locator('#hb-jour-2 .hb-toi', has_text='Vidéo 2').locator('input').check()
        page.wait_for_timeout(400)
        if envois[-1:] != [{'semaine': LUNDI, 'cle': 'mer-video', 'fait': True}]: erreurs.append(f'{nom} : envoi inattendu {envois[-1:]}')
        if page.locator('#hb-jour-2 .hb-fait', has_text='Vidéo 2').count() != 1: erreurs.append(f'{nom} : vidéo 2 non barrée')
        # La décocher
        page.locator('#hb-jour-2 .hb-toi', has_text='Vidéo 2').locator('input').uncheck()
        page.wait_for_timeout(400)
        if envois[-1] != {'semaine': LUNDI, 'cle': 'mer-video', 'fait': False}: erreurs.append(f'{nom} : décoche inattendue {envois[-1]}')
        if page.locator('#hb-jour-2 .hb-fait').count() != (1 if JOUR == 'mer' else 0): erreurs.append(f'{nom} : vidéo 2 toujours barrée')
        # Tâche du mois : rangée au 1er du mois
        page.locator('#hb-mois .hb-toi', has_text='Relevé SeLoger').locator('input').check()
        page.wait_for_timeout(400)
        if envois[-1] != {'semaine': PREMIER, 'cle': 'm-releve-seloger', 'fait': True}: erreurs.append(f'{nom} : tâche du mois {envois[-1]}')
        # Filtre « À faire seulement » : plus de robots ni de rappels visibles
        page.click('#hb-filtres button[data-f="toi"]')
        page.wait_for_timeout(200)
        vis = page.eval_on_selector_all('.hb-robot, .hb-rappel', 'els => els.filter(e => e.offsetParent).length')
        if vis: erreurs.append(f'{nom} : {vis} robots ou rappels encore visibles avec le filtre')
        if nom == 'iphone':
            page.screenshot(path=str(SORTIE / 'taches_hebdo_iphone_filtre.png'))
            larg = page.evaluate('document.documentElement.scrollWidth')
            if larg > 392: erreurs.append(f'iphone : la page déborde ({larg}px)')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tâches hebdomadaires : tout est bon')
sys.exit(1 if erreurs else 0)
