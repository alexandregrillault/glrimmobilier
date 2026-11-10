# Test du filtre « plusieurs villes » de l'onglet Contacts (10/11/2026) : pastilles,
# union des villes, rayon autour de chacune, texte tapé pris en compte, retrait. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/contacts_villes.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

CONTACTS = [
    {'id': 'a', 'nom': 'Client Clamart', 'email': 'a@x.fr', 'lieu': 'Clamart 92140', 'statut': 'Nouveau', 'vendeur': ''},
    {'id': 'b', 'nom': 'Client Sceaux', 'email': 'b@x.fr', 'lieu': 'Sceaux 92330', 'statut': 'Nouveau', 'vendeur': ''},
    {'id': 'c', 'nom': 'Client Antony', 'email': 'c@x.fr', 'lieu': 'Antony 92160', 'statut': 'Nouveau', 'vendeur': ''},
    {'id': 'd', 'nom': 'Client Lyon', 'email': 'd@x.fr', 'lieu': 'Lyon 69003', 'statut': 'Nouveau', 'vendeur': ''},
]
# Clamart → Antony ≈ 5,8 km ; Clamart → Sceaux ≈ 3,5 km ; Sceaux → Antony ≈ 2,6 km
COMMUNES = [
    {'nom': 'Clamart', 'codesPostaux': ['92140'], 'centre': {'type': 'Point', 'coordinates': [2.2667, 48.8003]}},
    {'nom': 'Sceaux', 'codesPostaux': ['92330'], 'centre': {'type': 'Point', 'coordinates': [2.2973, 48.7766]}},
    {'nom': 'Antony', 'codesPostaux': ['92160'], 'centre': {'type': 'Point', 'coordinates': [2.2975, 48.7533]}},
    {'nom': 'Lyon', 'codesPostaux': ['69003'], 'centre': {'type': 'Point', 'coordinates': [4.8357, 45.7640]}},
]

def geo(url):
    if 'codePostal=' in url:
        cp = url.split('codePostal=')[1].split('&')[0]
        return [c for c in COMMUNES if cp in c['codesPostaux']][:1]
    if 'communes?fields=centre,nom,codesPostaux' in url:
        return COMMUNES
    return []

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        def repond(r):
            u = r.request.url
            if 'geo.api.gouv.fr' in u: return r.fulfill(status=200, content_type='application/json', body=json.dumps(geo(u)))
            if 'supabase.co' in u: return r.fulfill(status=200, content_type='application/json', body='[]')
            return r.continue_()
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if not x.endswith(': ok')]
            print(len(res), 'blocs de script vérifiés')
        page.evaluate("""c => { _hideLogin(); document.querySelectorAll('.page').forEach(x => x.classList.remove('active'));
            document.getElementById('page-contacts').classList.add('active'); window._contacts = c; renderContacts(); }""", CONTACTS)

        def visibles():
            return sorted(page.eval_on_selector_all('#contacts-tbody .contact-cb', 'l => l.map(x => x.dataset.id)'))
        def attendre(ids, etape):
            try: page.wait_for_function('ids => JSON.stringify([...document.querySelectorAll("#contacts-tbody .contact-cb")].map(x => x.dataset.id).sort()) === JSON.stringify(ids)', arg=ids, timeout=4000)
            except Exception: erreurs.append(f'{nom} : {etape} : attendu {ids}, obtenu {visibles()}')

        page.evaluate("filtreLieuChoisi('Clamart 92140')")
        attendre(['a'], 'une ville')
        page.evaluate("filtreLieuChoisi('Sceaux 92330')")
        attendre(['a', 'b'], 'deux villes')
        page.evaluate("filtreLieuChoisi('sceaux 92330')")   # doublon ignoré
        if page.evaluate('_filtreLieux.length') != 2: erreurs.append(f'{nom} : doublon ajouté')
        if page.locator('#filter-lieu-chips').inner_text().count('✕') != 2: erreurs.append(f'{nom} : pastilles : {page.locator("#filter-lieu-chips").inner_text()}')
        if 'Effacer les villes' not in page.locator('#filter-lieu-chips').inner_text(): erreurs.append(f'{nom} : pas de bouton « Effacer les villes »')
        if page.input_value('#filter-lieu') != '': erreurs.append(f'{nom} : le champ ne se vide pas après le choix')

        page.fill('#filter-rayon', '3'); page.evaluate('updateRayonFilter()')
        attendre(['a', 'b', 'c'], 'rayon 3 km autour des deux villes')
        page.screenshot(path=str(SORTIE / f'contacts_villes_{nom}.png'))

        page.evaluate("filtreLieuRetire('Sceaux 92330')")
        attendre(['a'], 'Sceaux retirée, rayon 3 km autour de Clamart seule')

        page.fill('#filter-rayon', '0'); page.evaluate('updateRayonFilter()')
        page.fill('#filter-lieu', 'lyon'); page.evaluate('renderContacts()')
        attendre(['a', 'd'], 'pastille + texte tapé')

        page.fill('#filter-lieu', ''); page.evaluate('filtreLieuxEffacer()')
        attendre(['a', 'b', 'c', 'd'], 'tout effacé')
        if page.locator('#filter-lieu-chips').is_visible(): erreurs.append(f'{nom} : pastilles encore visibles')

        if nom == 'iphone':
            larg = page.evaluate('document.documentElement.scrollWidth')
            if larg > 400: erreurs.append(f'iphone : la page déborde ({larg} px)')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'OK — filtre plusieurs villes')
sys.exit(1 if erreurs else 0)
