# Test de « Pas de réponse » sur un client avancé (décision d'Alex du 11/11/2026) :
# en Suivi, Sélections, Retour documentation ou Finaliser la vente, le statut ne bouge pas,
# on note seulement l'appel (RPC contact_appel_sans_reponse) ; un « Nouveau » passe
# toujours en « Sans réponse ». Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/appel_garde_statut.py [dossier des captures]
import datetime, json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

MAINTENANT = datetime.datetime.now(datetime.timezone.utc).isoformat()
HIER = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).isoformat()
def lead(i, nom, statut, **k):
    l = {'id': i, 'nom': nom, 'prenom': 'Claire', 'statut': statut, 'vendeur': 'Louis', 'date_lead': '2026-10-01',
         'recu_le': '2026-10-01T10:00:00+02:00', 'statut_maj': '2026-10-20T10:00:00+02:00',
         'derniere_action_le': '2026-10-20T10:00:00+02:00', 'appels': [], 'telephone': '06 12 34 56 78'}
    l.update(k)
    return l
LEADS = [
    lead('r', 'Retour', 'Retour documentation', appels=[{'le': HIER, 'vendeur': 'Louis'}]),
    lead('f', 'Finaliser', 'Finaliser la vente'),
    lead('n', 'Nouveau', 'Nouveau'),
]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        rpc, patchs, refus = [], [], {'f': False}
        appels_base = {'r': [{'le': HIER, 'vendeur': 'Louis'}, {'le': MAINTENANT, 'vendeur': 'Louis'}]}
        def repond(r):
            u, m = r.request.url, r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rpc/contact_appel_sans_reponse' in u:
                corps = json.loads(r.request.post_data)
                rpc.append(corps['p_id'])
                if corps['p_id'] == 'f' and refus['f']:
                    return r.fulfill(status=400, content_type='application/json', body=json.dumps({'message': 'Modification refusée sur ce client'}))
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(appels_base.get(corps['p_id'], [])))
            if '/contacts?select=appels' in u:
                i = u.split('id=eq.')[1]
                return r.fulfill(status=200, content_type='application/json', body=json.dumps([{'appels': appels_base.get(i, [])}]))
            if m == 'PATCH' and '/contacts' in u:
                patchs.append(json.loads(r.request.post_data))
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("ls => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = []; _eqSelections = {}; }", LEADS)

        # Retour documentation : clic sur le bouton de la fiche
        page.evaluate("eqOuvrirFiche('r')")
        page.wait_for_timeout(300)
        page.get_by_role('button', name='Pas de réponse', exact=True).first.click()
        page.wait_for_timeout(500)
        if rpc != ['r']: erreurs.append(f'{nom} : RPC appelée {rpc} au lieu de [r]')
        if any('statut' in x for x in patchs): erreurs.append(f'{nom} : statut écrit sur la fiche : {patchs}')
        st = page.evaluate("eqLeadStatut(_eqLeads.find(l => l.id === 'r'))")
        if st != 'Retour documentation': erreurs.append(f'{nom} : statut devenu {st}')
        n = page.evaluate("_eqLeads.find(l => l.id === 'r').appels.length")
        if n != 2: erreurs.append(f'{nom} : {n} appels sur la fiche au lieu de 2')
        txt = page.inner_text('body')
        if "2 tentatives d'appel" not in txt.replace('’', "'").lower(): erreurs.append(f'{nom} : tentatives non affichées sur la fiche')
        if 'reste en « Retour documentation »' not in txt: erreurs.append(f'{nom} : message de confirmation absent')
        page.screenshot(path=str(SORTIE / f'appel_garde_statut_{nom}.png'))

        # Refus de la base : message d'erreur, rien d'autre
        refus['f'] = True
        page.evaluate("eqAppelSansReponse('f')")
        page.wait_for_timeout(400)
        if 'Appel non noté' not in page.inner_text('body'): erreurs.append(f'{nom} : refus de la base non signalé')
        if any('statut' in x for x in patchs): erreurs.append(f'{nom} : statut écrit après un refus : {patchs}')

        # Nouveau : passe toujours en « Sans réponse », sans la RPC
        avant = len(rpc)
        page.evaluate("eqAppelSansReponse('n')")
        page.wait_for_timeout(400)
        if len(rpc) != avant: erreurs.append(f'{nom} : RPC appelée pour un Nouveau')
        if not any(x.get('statut') == 'Sans réponse' for x in patchs): erreurs.append(f'{nom} : Nouveau pas passé en Sans réponse : {patchs}')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
