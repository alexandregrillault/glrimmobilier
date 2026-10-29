# Test de l'offre GLR sur une vente : case dans la fiche, enregistrement, commission vendeur
# = (honoraires − offre) × taux, chiffre d'affaires net, facture promoteur inchangée. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/ventes_offre.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

VENDEURS = [{'id': 'v1', 'prenom': 'Louis', 'nom': 'Test', 'tauxDefaut': 30}]
VENTES = [
    {'id': 'a', 'programme': 'Scène 3', 'client': 'Client A', 'vendeurId': 'v1', 'prix': 300000, 'tauxHonoraires': 5, 'honoraires': 15000,
     'offreGlr': 1000, 'taux': 30, 'date': '2026-10-10', 'dateActe': '', 'dateSignatureNotaire': '', 'statut': 'reservation', 'promoteur': 'Promo'},
    {'id': 'b', 'programme': 'Hameau du Lac', 'client': 'Client B', 'vendeurId': 'v1', 'prix': 200000, 'tauxHonoraires': 5, 'honoraires': 10000,
     'offreGlr': 0, 'taux': 30, 'date': '2026-10-12', 'dateActe': '', 'dateSignatureNotaire': '', 'statut': 'reservation', 'promoteur': 'Promo'},
]
ECRITS = []

def route(r):
    u, m = r.request.url, r.request.method
    if 'supabase.co' not in u: return r.continue_()
    if '/rest/v1/ventes' in u and m in ('PATCH', 'POST'):
        ECRITS.append(json.loads(r.request.post_data))
    return r.fulfill(status=200, content_type='application/json', body='[]')

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        ECRITS.clear()
        page = nav.new_page(viewport=vp)
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""([vd, vt]) => { _hideLogin(); data.vendeurs = vd; data.ventes = vt.map(rowToVente); }""", [VENDEURS, VENTES])

        # Calculs
        r = page.evaluate("""() => ({ net: honoNet(data.ventes[0]), com: commissionVente(data.ventes[0]), comB: commissionVente(data.ventes[1]),
                                      ligne: venteToRow(data.ventes[1]).offreGlr })""")
        if r['net'] != 14000: erreurs.append(f'{nom} : net {r["net"]} au lieu de 14000')
        if r['com'] != 4200: erreurs.append(f'{nom} : commission {r["com"]} au lieu de 4200 (14 000 × 30 %)')
        if r['comB'] != 3000: erreurs.append(f'{nom} : commission sans offre {r["comB"]} au lieu de 3000')
        if r['ligne'] is not None: erreurs.append(f'{nom} : offre vide envoyée {r["ligne"]!r} au lieu de null')

        # Fiche vente : la case, l'aperçu, l'enregistrement
        page.evaluate("openEditVente('a')")
        page.wait_for_selector('#modal-vente.open')
        if page.input_value('#v-offre-glr') != '1000': erreurs.append(f'{nom} : offre non reprise dans la fiche')
        page.fill('#v-offre-glr', '1500')
        hint = page.text_content('#v-offre-hint').replace(' ', ' ').replace('\xa0', ' ')
        if '13 500' not in hint or '4 050' not in hint: erreurs.append(f'{nom} : aperçu inattendu : {hint}')
        page.locator('#v-offre-glr').scroll_into_view_if_needed()
        page.screenshot(path=str(SORTIE / f'ventes_offre_{nom}.png'))
        page.evaluate("saveVente()")
        page.wait_for_timeout(300)
        if not ECRITS or ECRITS[-1].get('offreGlr') != 1500: erreurs.append(f'{nom} : offre non envoyée en base : {ECRITS[-1:]}')
        elif ECRITS[-1].get('honoraires') != 15000: erreurs.append(f'{nom} : honoraires facturés modifiés : {ECRITS[-1].get("honoraires")}')

        # Facture promoteur : toujours sur les honoraires bruts
        fac = page.evaluate("() => _facHtRetenu(data.ventes[0].prix, data.ventes[0].tauxHonoraires, Number(data.ventes[0].honoraires) || 0)")
        if fac != 15000: erreurs.append(f'{nom} : facture promoteur {fac} au lieu de 15000')

        # Page Ventes : CA net (13 500 + 10 000)
        page.evaluate("() => { goTo('ventes', null); refresh(); }")
        page.wait_for_timeout(300)
        ca = page.text_content('#kpi-ca').replace(' ', ' ').replace('\xa0', ' ')
        if '23 500' not in ca: erreurs.append(f'{nom} : CA affiché {ca} au lieu de 23 500')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
