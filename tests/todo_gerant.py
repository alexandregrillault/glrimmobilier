# Test de la todo des gérants (demande d'Alex du 12/11/2026) : étapes rangées par sujet,
# cocher une étape la retire et l'enregistre, historique par jour avec « Remettre »,
# ajout d'une étape (sujet existant ou nouveau), pastille du menu. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/todo_gerant.py [dossier des captures]
import datetime, json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def il_y_a(h):
    return (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=h)).isoformat()
TODO = [
    {'id': 'a1', 'sujet': 'Plan 3D des appartements', 'etape': 'Générer à la demande ou tout d’avance ?', 'ordre': 1, 'cree_le': il_y_a(240), 'cree_par': 'Claude', 'fait_le': None, 'fait_par': None},
    {'id': 'a2', 'sujet': 'Plan 3D des appartements', 'etape': 'Avec ou sans mobilier ?', 'ordre': 2, 'cree_le': il_y_a(240), 'cree_par': 'Claude', 'fait_le': None, 'fait_par': None},
    {'id': 'b1', 'sujet': 'Dénonciation : promoteurs que le robot ne fait pas', 'etape': 'Refusent le robot : Catella, Nexity, Demathieu Bard, Green City, ODEA', 'ordre': 1, 'cree_le': il_y_a(20), 'cree_par': 'Claude', 'fait_le': None, 'fait_par': None},
    {'id': 'b2', 'sujet': 'Dénonciation : promoteurs que le robot ne fait pas', 'etape': 'Vinci (dénonciation par mail)', 'ordre': 2, 'cree_le': il_y_a(20), 'cree_par': 'Alex', 'fait_le': il_y_a(3), 'fait_par': 'Alex'},
    {'id': 'c1', 'sujet': 'Tickets vendeurs', 'etape': 'Mettre en ligne', 'ordre': 1, 'cree_le': il_y_a(30), 'cree_par': 'Claude', 'fait_le': il_y_a(28), 'fait_par': 'Claude'},
]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        donnees = json.loads(json.dumps(TODO))
        ajouts, maj = [], []
        def repond(r):
            u, m = r.request.url, r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rest/v1/gerant_todo' in u and m == 'POST':
                o = json.loads(r.request.post_data); ajouts.append(o)
                donnees.append(dict(o, id='n%d' % len(ajouts), cree_le=il_y_a(0), cree_par='Alex', fait_le=None, fait_par=None))
                return r.fulfill(status=201, body='')
            if '/rest/v1/gerant_todo' in u and m == 'PATCH':
                i = u.split('id=eq.')[1]; corps = json.loads(r.request.post_data); maj.append((i, corps))
                for t in donnees:
                    if t['id'] == i:
                        t['fait_le'] = corps['fait_le']; t['fait_par'] = 'Alex' if corps['fait_le'] else None
                return r.fulfill(status=204, body='')
            if '/rest/v1/gerant_todo' in u:
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(donnees))
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]

        page.evaluate("() => { _hideLogin(); MON_ROLE = { prenom: 'Alex', role: 'gerant' }; }")
        page.evaluate("goTo('gerant-todo', null)")
        page.wait_for_timeout(400)
        sujets = page.eval_on_selector_all('#td-liste .td-sujet', 'els => els.map(e => e.innerText.split("\\n")[0])')
        if sujets != ['Plan 3D des appartements', 'Dénonciation : promoteurs que le robot ne fait pas']:
            erreurs.append(f'{nom} : sujets inattendus {sujets}')
        if page.locator('#td-liste .td-etape').count() != 3: erreurs.append(f'{nom} : il faut 3 étapes à faire')
        if 'Vinci' in page.inner_text('#td-liste'): erreurs.append(f'{nom} : une étape faite est encore dans la liste')
        if page.inner_text('#nav-todo-pastille') != '3': erreurs.append(f'{nom} : pastille {page.inner_text("#nav-todo-pastille")!r}')
        page.screenshot(path=str(SORTIE / f'todo_liste_{nom}.png'))

        # Cocher « Avec ou sans mobilier ? »
        page.locator('#td-liste .td-etape', has_text='mobilier').locator('input').check()
        page.wait_for_timeout(700)
        if maj[-1:] and maj[-1][0] != 'a2': erreurs.append(f'{nom} : mauvaise étape cochée {maj}')
        if not maj or not maj[-1][1].get('fait_le'): erreurs.append(f'{nom} : coche non envoyée')
        if 'mobilier' in page.inner_text('#td-liste'): erreurs.append(f'{nom} : étape cochée toujours affichée')
        if page.inner_text('#nav-todo-pastille') != '2': erreurs.append(f'{nom} : pastille après coche')

        # Ajouter une étape au sujet Dénonciation par le bouton du bloc
        page.locator('#td-liste .td-sujet', has_text='Dénonciation').locator('button', has_text='Ajouter une étape').click()
        if page.input_value('#td-sujet') != 'Dénonciation : promoteurs que le robot ne fait pas': erreurs.append(f'{nom} : sujet non prérempli')
        page.fill('#td-etape', '  Appeler   Kaufman ')
        page.press('#td-etape', 'Enter')
        page.wait_for_timeout(500)
        if not ajouts or ajouts[-1] != {'sujet': 'Dénonciation : promoteurs que le robot ne fait pas', 'etape': 'Appeler Kaufman', 'ordre': 3}:
            erreurs.append(f'{nom} : ajout inattendu {ajouts}')
        if 'Appeler Kaufman' not in page.inner_text('#td-liste'): erreurs.append(f'{nom} : étape ajoutée absente')
        # Étape vide refusée
        n = len(ajouts); page.fill('#td-etape', ''); page.click('#td-ajout button'); page.wait_for_timeout(200)
        if len(ajouts) != n: erreurs.append(f'{nom} : étape vide envoyée')

        # Historique
        page.click('#td-filtres button[data-f="histo"]')
        page.wait_for_timeout(200)
        h = page.inner_text('#td-liste')
        for attendu in ('Vinci', 'mobilier', 'Mettre en ligne', 'par Alex'):
            if attendu not in h: erreurs.append(f'{nom} : historique sans « {attendu} »')
        if page.is_visible('#td-ajout'): erreurs.append(f'{nom} : formulaire d’ajout visible dans l’historique')
        page.screenshot(path=str(SORTIE / f'todo_historique_{nom}.png'))
        page.locator('.td-fait', has_text='Vinci').locator('button', has_text='Remettre').click()
        page.wait_for_timeout(400)
        if maj[-1] != ('b2', {'fait_le': None}): erreurs.append(f'{nom} : « Remettre » inattendu {maj[-1]}')
        page.click('#td-filtres button[data-f="afaire"]')
        page.wait_for_timeout(200)
        if 'Vinci' not in page.inner_text('#td-liste'): erreurs.append(f'{nom} : étape remise absente de la liste')

        if nom == 'iphone':
            larg = page.evaluate('document.documentElement.scrollWidth')
            if larg > 392: erreurs.append(f'iphone : la page déborde ({larg}px)')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Todo gérants : tout est bon')
sys.exit(1 if erreurs else 0)
