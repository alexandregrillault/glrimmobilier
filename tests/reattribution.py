# Test de la réattribution groupée (bug du 12/11/2026 : « parfois ils ne partent pas tous ») :
# fiches relues en base (même hors de la liste affichée), transfert vérifié dans la réponse,
# bilan transférés / déjà chez lui / échecs (qui restent cochés), et rechargement de la liste
# jamais perdu quand un rafraîchissement de fond tourne déjà. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/reattribution.py [dossier des captures]
import json, pathlib, sys, urllib.parse
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def uid(c): return f'00000000-0000-4000-8000-00000000000{c}'
A, B, C, D, E, Z = (uid(x) for x in 'abcdef')
def lead(i, nom, vendeur='Louis'):
    p, f = nom.split(' ')
    return {'id': i, 'nom': nom, 'prenom': p, 'nom_famille': f, 'statut': 'Suivi', 'vendeur': vendeur, 'vendeur_depuis': '2026-10-01T10:00:00Z',
            'vendeur_historique': [{'vendeur': 'Anais', 'du': None, 'au': '2026-10-01T10:00:00Z', 'motif': 'réattribution'}], 'date_lead': '2026-10-01', 'appels': []}
AFFICHES = [lead(A, 'Anne Alpha'), lead(B, 'Bruno Beta'), lead(C, 'Chloe Gamma'), lead(D, 'Denis Delta')]
BASE = {A: lead(A, 'Anne Alpha'), B: lead(B, 'Bruno Beta'), C: lead(C, 'Chloe Gamma'), D: lead(D, 'Denis Delta', 'Jules'), E: lead(E, 'Emma Epsilon')}
VENDEURS = [{'id': 'v1', 'prenom': 'Louis', 'nom': 'G'}, {'id': 'v2', 'prenom': 'Jules', 'nom': 'F'}]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        alertes, patchs = [], {}
        def dialogue(d):
            if d.type == 'alert': alertes.append(d.message)
            d.accept()
        page.on('dialog', dialogue)
        def repond(r):
            u, m = urllib.parse.unquote(r.request.url), r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rest/v1/contacts' in u and m == 'GET' and 'id=in.(' in u:
                ids = u.split('id=in.(')[1].split(')')[0].split(',')
                return r.fulfill(status=200, content_type='application/json', body=json.dumps([BASE[i] for i in ids if i in BASE]))
            if '/rest/v1/contacts' in u and m == 'PATCH':
                i = u.split('id=eq.')[1].split('&')[0]
                patchs[i] = json.loads(r.request.post_data)
                if i == C: return r.fulfill(status=200, content_type='application/json', body='[]')   # la base n'a rien changé
                return r.fulfill(status=200, content_type='application/json', body=json.dumps([{'id': i, 'vendeur': patchs[i]['vendeur']}]))
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""([ls, vd, sel]) => {
            _hideLogin(); MON_ROLE = { prenom: 'Alexandre', role: 'gerant' }; data.vendeurs = vd;
            goTo('equipe-leads', null);
            window._rechargements = 0;
            // Liste « rechargée » : lente, comme en vrai ; elle reprend l'état des fiches affichées
            renderEquipeLeads = async () => { window._rechargements++; await new Promise(r => setTimeout(r, 250)); _eqLeads = _eqLeads.filter(l => l.vendeur === 'Louis'); renderEquipeLeadsTable(); };
            _eqLeads = ls; _eqSelected.clear(); sel.forEach(id => _eqSelected.add(id)); renderEquipeLeadsTable();
        }""", [AFFICHES, VENDEURS, [A, B, C, D, E, Z]])
        page.screenshot(path=str(SORTIE / f'reattribution_avant_{nom}.png'))
        # Un rafraîchissement de fond démarre (retour sur la fenêtre) juste avant la réattribution
        bilan = page.evaluate("""async () => {
            _majDerniere = 0; window.dispatchEvent(new Event('focus'));
            const sel = document.createElement('select'); sel.innerHTML = '<option value="Jules">Jules</option>'; sel.value = 'Jules';
            const b = await eqSelVendeur(sel);
            await new Promise(r => setTimeout(r, 700));
            return b;
        }""")
        if sorted(bilan['faits']) != sorted([A, B, E]): erreurs.append(f'{nom} : transférés {bilan["faits"]}')
        if bilan['deja'] != [D]: erreurs.append(f'{nom} : déjà chez Jules {bilan["deja"]}')
        if sorted(bilan['echecs']) != sorted([C, Z]): erreurs.append(f'{nom} : échecs {bilan["echecs"]}')
        if E not in patchs: erreurs.append(f'{nom} : la fiche hors liste n’a pas été transférée')
        h = (patchs.get(A) or {}).get('vendeur_historique') or []
        if len(h) != 2 or h[-1].get('vendeur') != 'Louis' or h[-1].get('motif') != 'réattribution groupée': erreurs.append(f'{nom} : historique {h}')
        coches = page.evaluate("[..._eqSelected]")
        if sorted(coches) != sorted([C, Z]): erreurs.append(f'{nom} : restent cochés {coches} au lieu des 2 échecs')
        msg = alertes[-1] if alertes else ''
        if '3 transférés à Jules' not in msg or '1 déjà chez Jules' not in msg or 'Chloe Gamma' not in msg or 'restent cochés' not in msg:
            erreurs.append(f'{nom} : bilan {msg!r}')
        n = page.evaluate("window._rechargements")
        if n < 2: erreurs.append(f'{nom} : {n} rechargement(s) : celui d’après la réattribution a été perdu')
        restants = page.evaluate("_eqLeads.map(l => l.id)")
        if sorted(restants) != sorted([C]): erreurs.append(f'{nom} : restent affichés {restants} au lieu du seul échec')
        page.screenshot(path=str(SORTIE / f'reattribution_apres_{nom}.png'))
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
