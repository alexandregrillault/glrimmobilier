# Test du filtre « Typologie » de l'onglet Contacts (10/11/2026) : lecture du texte libre
# (« Appartement 3 pièces, T2, T3 », « Villa », « studio »…), cases cochées, typologie inconnue, export. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/contacts_typo.py [dossier des captures]
import pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def ct(i, typo): return {'id': i, 'nom': 'Client ' + i, 'email': i + '@x.fr', 'lieu': 'Clamart 92140', 'statut': 'Nouveau', 'vendeur': '', 'typologie': typo}
CONTACTS = [ct('a', 'Appartement 3 pièces, T2, T3'), ct('b', 'Appartement 4 pièces'), ct('c', 'Villa 3 pièces'),
            ct('d', None), ct('e', 'Studio'), ct('f', 'T5+'), ct('g', 'Appartement 6 pièces'), ct('h', 'Villa')]
ATTENDU = {'a': ['T2', 'T3'], 'b': ['T4'], 'c': ['Maison', 'T3'], 'd': ['inconnue'], 'e': ['T1'], 'f': ['T5+'], 'g': ['T5+'], 'h': ['Maison']}

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.route('**/*', lambda r: r.fulfill(status=200, content_type='application/json', body='[]') if ('supabase.co' in r.request.url or 'geo.api' in r.request.url) else r.continue_())
        page.goto(INDEX.as_uri())
        page.evaluate("""c => { _hideLogin(); document.querySelectorAll('.page').forEach(x => x.classList.remove('active'));
            document.getElementById('page-contacts').classList.add('active'); window._contacts = c; renderContacts(); }""", CONTACTS)
        if nom == 'bureau':
            lu = page.evaluate("c => Object.fromEntries(c.map(x => [x.id, typosContact(x).sort()]))", CONTACTS)
            for k, v in ATTENDU.items():
                if lu[k] != sorted(v): erreurs.append(f'lecture {k} : attendu {sorted(v)}, obtenu {lu[k]}')
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if x != 'ok']

        def visibles(): return sorted(page.eval_on_selector_all('#contacts-tbody .contact-cb', 'l => l.map(x => x.dataset.id)'))
        def verifie(ids, etape):
            if visibles() != ids: erreurs.append(f'{nom} : {etape} : attendu {ids}, obtenu {visibles()}')

        verifie(list('abcdefgh'), 'sans filtre')
        page.click('#filter-typo-btn')
        if not page.locator('#filter-typo-menu').is_visible(): erreurs.append(f'{nom} : menu fermé')
        page.locator('#filter-typo-menu label', has_text='T3').locator('input').check()
        verifie(['a', 'c'], 'T3')
        page.locator('#filter-typo-menu label', has_text='T4').locator('input').check()
        verifie(['a', 'b', 'c'], 'T3 + T4')
        if 'T3 + T4' not in page.inner_text('#filter-typo-btn'): erreurs.append(f'{nom} : bouton : {page.inner_text("#filter-typo-btn")}')
        page.locator('#filter-typo-menu label', has_text='inconnue').locator('input').check()
        verifie(['a', 'b', 'c', 'd'], 'T3 + T4 + inconnue')
        page.screenshot(path=str(SORTIE / f'contacts_typo_{nom}.png'))
        page.mouse.click(5, 5)
        if page.locator('#filter-typo-menu').is_visible(): erreurs.append(f'{nom} : menu pas refermé au clic dehors')
        page.evaluate("filtreTyposVider(); filtreTypoToggle('Maison', true)")
        verifie(['c', 'h'], 'Maison')
        if nom == 'bureau':
            n = page.evaluate("""() => { let rows = null; const B = window.Blob; window.Blob = function(parts, o) { rows = parts.join(''); return new B(parts, o); };
                try { exportContacts('brevo'); } catch (e) {} window.Blob = B; return rows; }""")
            if n is None or 'c@x.fr' not in n or 'a@x.fr' in n: erreurs.append(f'export Brevo ne suit pas le filtre : {n!r}')
        page.evaluate('filtreTyposVider()')
        verifie(list('abcdefgh'), 'tout effacé')
        if nom == 'iphone':
            larg = page.evaluate('document.documentElement.scrollWidth')
            if larg > 400: erreurs.append(f'iphone : la page déborde ({larg} px)')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'OK — filtre typologie')
sys.exit(1 if erreurs else 0)
