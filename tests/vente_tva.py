# Test de la TVA au passage en Vendu (demande d'Alex du 03/11/2026) : choix TVA 20 % / 5,5 %,
# prix repris des régimes de la sélection, prix 5,5 % demandé quand la sélection ne le donne pas,
# TVA et prix transmis dans vente_lot ; fiche vente du gérant (liste TVA, préremplissage). Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/vente_tva.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

LEADS = [{'id': 'c1', 'nom': 'Client Test', 'prenom': '', 'statut': 'Finaliser la vente', 'vendeur': 'Louis', 'date_lead': '2026-10-01', 'appels': []}]
SELECTIONS = [{'token': 's1', 'contact_id': 'c1', 'biens': [
    {'titre': 'Scène 3 — A106', 'ville': 'Drancy', 'prix': '230 900 €', 'programme': 'Scène 3', 'lot': 'A106',
     'prixOptions': [{'tva': 20, 'prix': 230900, 'prixTexte': '230 900 €'}, {'tva': 10, 'prix': 211658}, {'tva': 5.5, 'prix': 203000, 'prixTexte': '203 000 €'}]},
    {'titre': 'Hameau — B12', 'ville': 'Bondy', 'prix': '320 000 €', 'programme': 'Hameau', 'lot': 'B12'},
]}]
net = lambda t: str(t).replace(' ', ' ').replace('\xa0', ' ')

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
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("([ls, ss]) => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = ss; _eqSelections = {}; }", [LEADS, SELECTIONS])

        # 1. Lot avec ses deux prix : les deux options s'affichent avec leur prix, 5,5 % retenu
        page.evaluate("eqLeadStatutChange('c1', 'Vendu')")
        page.wait_for_selector('#vl-taux')
        page.select_option('#vl-choix', '0')
        b20, b55 = net(page.inner_text('#vl-tva-20')), net(page.inner_text('#vl-tva-55'))
        if '230 900 €' not in b20 or '203 000 €' not in b55: erreurs.append(f'{nom} : prix des options : {b20!r} / {b55!r}')
        page.fill('#vl-taux', '5')
        page.click('#vl-tva-55')
        if '10 150 €' not in net(page.inner_text('#vl-taux-apercu')): erreurs.append(f'{nom} : aperçu 5,5 % : {page.inner_text("#vl-taux-apercu")}')
        if not page.is_visible('#vl-tva-note'): erreurs.append(f'{nom} : pas de note TVA réduite')
        if page.is_visible('#vl-prix-tva'): erreurs.append(f'{nom} : prix demandé alors qu il est connu')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : déborde en largeur')
        page.screenshot(path=str(SORTIE / f'vente_tva_{nom}.png'))
        page.evaluate("eqVenteLotValider()")
        page.wait_for_timeout(200)
        vl = ecrits[-1]['vente_lot'] if ecrits else {}
        if vl.get('tva') != 5.5 or net(vl.get('prix')) != '203 000 €' or vl.get('prix_tva20') != 230900:
            erreurs.append(f'{nom} : vente 5,5 % envoyée : {vl}')

        # 2. Lot sans prix 5,5 % connu : le prix est demandé, la vente bloquée sans lui
        ecrits.clear()
        page.evaluate("eqLeadStatutChange('c1', 'Vendu')")
        page.wait_for_selector('#vl-taux')
        page.select_option('#vl-choix', '1')
        page.fill('#vl-taux', '5')
        page.click('#vl-tva-55')
        if not page.is_visible('#vl-prix-tva'): erreurs.append(f'{nom} : prix 5,5 % non demandé')
        page.evaluate("eqVenteLotValider()")
        if ecrits: erreurs.append(f'{nom} : vente 5,5 % acceptée sans prix')
        if 'TVA 5,5' not in page.inner_text('#vl-erreur'): erreurs.append(f'{nom} : message sans prix 5,5 %')
        page.fill('#vl-prix-tva', '290 000')
        page.evaluate("eqVenteLotValider()")
        page.wait_for_timeout(200)
        vl = ecrits[-1]['vente_lot'] if ecrits else {}
        if vl.get('tva') != 5.5 or net(vl.get('prix')) != '290 000 €': erreurs.append(f'{nom} : vente saisie : {vl}')

        # 3. Par défaut : TVA 20 % au prix de la sélection, comme avant
        ecrits.clear()
        page.evaluate("eqLeadStatutChange('c1', 'Vendu')")
        page.wait_for_selector('#vl-taux')
        page.select_option('#vl-choix', '1')
        page.fill('#vl-taux', '5')
        page.evaluate("eqVenteLotValider()")
        page.wait_for_timeout(200)
        vl = ecrits[-1]['vente_lot'] if ecrits else {}
        if vl.get('tva') != 20 or net(vl.get('prix')) != '320 000 €' or vl.get('prix_tva20') is not None: erreurs.append(f'{nom} : vente 20 % : {vl}')

        # 4. Fiche vente du gérant : la TVA se relit, se garde et s'affiche dans la liste
        r = page.evaluate("""() => {
            const v = rowToVente({ id: 'v1', programme: 'Scène 3', prix: '203000', tva: '5.5', vendeurId: '', date: '2026-11-03', statut: 'reservation' });
            data.ventes = [v];
            openEditVente('v1');
            const lu = document.getElementById('v-tva').value;
            closeModal('vente');
            return { tva: v.tva, lu, apresReset: document.getElementById('v-tva').value, mention: venteTvaMention(v), ancien: rowToVente({ prix: 1 }).tva };
        }""")
        if r != {'tva': 5.5, 'lu': '5.5', 'apresReset': '20', 'mention': r.get('mention'), 'ancien': 20} or 'TVA 5,5' not in r.get('mention', ''):
            erreurs.append(f'{nom} : fiche vente gérant : {r}')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon')
sys.exit(1 if erreurs else 0)
