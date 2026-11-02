# Test du taux de commission au passage en Vendu : champ obligatoire, virgule acceptée, aperçu
# des honoraires, taux transmis dans vente_lot, passage groupé en Vendu refusé. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/vente_taux.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

LEADS = [{'id': 'c1', 'nom': 'Client Test', 'prenom': '', 'statut': 'Finaliser la vente', 'vendeur': 'Louis', 'date_lead': '2026-10-01', 'appels': []}]
SELECTIONS = [{'token': 's1', 'contact_id': 'c1', 'biens': [{'titre': 'Scène 3 — A106', 'ville': 'Drancy', 'prix': '320 000 €', 'programme': 'Scène 3', 'lot': 'A106'}]}]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        ecrits = []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if r.request.method == 'PATCH' and '/contacts' in r.request.url: ecrits.append(json.loads(r.request.post_data))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("([ls, ss]) => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = ss; _eqSelections = {}; }", [LEADS, SELECTIONS])
        page.evaluate("eqLeadStatutChange('c1', 'Vendu')")
        page.wait_for_selector('#vl-taux')

        # Le champ est au-dessus du lot, visible d'entrée, et bloque sans taux
        page.select_option('#vl-choix', '0')
        page.evaluate("eqVenteLotValider()")
        if ecrits: erreurs.append(f'{nom} : vente acceptée sans taux')
        if not page.is_visible('#vl-taux-erreur'): erreurs.append(f'{nom} : pas de message sans taux')
        for faux in ('0', '60', 'abc', '5,2,5'):
            page.fill('#vl-taux', faux)
            page.evaluate("eqVenteLotValider()")
            if ecrits: erreurs.append(f'{nom} : taux {faux} accepté')

        # Virgule acceptée, à la décimale près, avec l'aperçu en euros
        page.fill('#vl-taux', '5,25')
        a = page.inner_text('#vl-taux-apercu').replace(' ', ' ').replace('\xa0', ' ')
        if '16 800 €' not in a: erreurs.append(f'{nom} : aperçu : {a}')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : déborde en largeur')
        page.screenshot(path=str(SORTIE / f'vente_taux_{nom}.png'))
        page.evaluate("eqVenteLotValider()")
        page.wait_for_timeout(200)
        if not ecrits or ecrits[0].get('statut') != 'Vendu': erreurs.append(f'{nom} : vente non envoyée : {ecrits}')
        elif ecrits[0]['vente_lot'].get('taux_honoraires') != 5.25: erreurs.append(f'{nom} : taux envoyé : {ecrits[0]["vente_lot"]}')

        # Le passage groupé en Vendu est refusé : il n'aurait ni lot ni taux
        ecrits.clear()
        page.on('dialog', lambda d: d.accept())
        page.evaluate("_eqLeads = [Object.assign({}, _eqLeads[0], {statut: 'Suivi'})]; _eqSelected = new Set(['c1']); _eqLeadsVisible = _eqLeads")
        page.evaluate("eqSelStatut({value: 'Vendu'})")
        page.wait_for_timeout(100)
        if 'fiche du client' not in page.evaluate("document.body.innerText"): erreurs.append(f'{nom} : pas de message sur le passage groupé')
        if any(e.get('statut') == 'Vendu' for e in ecrits): erreurs.append(f'{nom} : passage groupé en Vendu accepté')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon')
sys.exit(1 if erreurs else 0)
