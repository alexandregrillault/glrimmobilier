# Anciens vendeurs (demande d'Alex du 24/11/2026 : « enlever Nour et Jules de la liste des vendeurs
# mais en gardant leur vente ») : un vendeur marqué « ancien » n'est plus sur la page Vendeurs ni
# dans les menus où l'on choisit un vendeur ; sa vente garde son nom et reste modifiable.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/anciens_vendeurs.py [dossier des captures]
import pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI
VENDEURS = [{'id': 'v1', 'prenom': 'Louis', 'nom': 'G', 'tauxDefaut': 30}, {'id': 'v2', 'prenom': 'Jules', 'nom': 'F', 'tauxDefaut': 30, 'ancien': True},
            {'id': 'v3', 'prenom': 'Nour', 'nom': 'H', 'tauxDefaut': 30, 'ancien': True}]
VENTES = [{'id': 's1', 'client': 'Client Jules', 'programme': 'Prog A', 'vendeurId': 'v2', 'statut': 'reservation', 'prix': 300000, 'honoraires': 9000, 'taux': 30, 'date': '2026-10-01'},
          {'id': 's2', 'client': 'Client Louis', 'programme': 'Prog B', 'vendeurId': 'v1', 'statut': 'reservation', 'prix': 250000, 'honoraires': 8000, 'taux': 30, 'date': '2026-10-02'}]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.route('**/*', lambda r: r.fulfill(status=200, content_type='application/json', body='[]') if 'supabase.co' in r.request.url else r.continue_())
        page.goto(INDEX.as_uri())
        def faux(cond, msg):
            if not cond: erreurs.append(f'{nom} : {msg}')
        page.evaluate("""([vd, vt]) => { _hideLogin(); MON_ROLE = { prenom: 'Alexandre', role: 'gerant' }; data.vendeurs = vd; data.ventes = vt; saveData = async () => {}; goTo('vendeurs', null); }""", [VENDEURS, VENTES])
        page.wait_for_timeout(300)
        grille = page.inner_text('#vendeur-grid')
        faux('Louis' in grille, 'Louis absent de la page Vendeurs')
        faux(page.locator('#vendeur-grid .vendeur-card', has_text='Jules').count() == 0 and page.locator('#vendeur-grid .vendeur-card', has_text='Nour').count() == 0, 'un ancien vendeur a encore sa carte')
        faux('Anciens vendeurs' in grille and 'Jules F' in grille and 'Nour H' in grille, f'ligne des anciens vendeurs absente : {grille[-200:]!r}')
        faux(page.inner_text('#vendeurs-count').startswith('1 '), 'le compteur compte encore les anciens')
        page.screenshot(path=str(SORTIE / f'anciens_vendeurs_{nom}.png'))
        # Les menus : nouvelle vente, planning, attribution
        page.evaluate("openModal('vente')")
        opts = page.evaluate("[...document.getElementById('v-vendeur').options].map(o => o.textContent)")
        faux('Louis G' in opts and 'Jules F' not in opts and 'Nour H' not in opts, f'menu de la nouvelle vente : {opts}')
        page.evaluate("closeModal('vente')")
        faux(page.evaluate("vendeursActifs().map(v => v.prenom).join(',')") == 'Louis', 'vendeursActifs')
        # Sa vente garde son nom, et reste modifiable avec lui dans le menu
        page.evaluate("goTo('ventes', null)")
        page.wait_for_timeout(300)
        txt = page.inner_text('#page-ventes')
        faux('Client Jules' in txt and 'Jules' in txt.replace('Client Jules', ''), 'la vente de Jules ne montre plus son nom')
        page.evaluate("openEditVente('s1')")
        opts = page.evaluate("[...document.getElementById('v-vendeur').options].filter(o => o.selected).map(o => o.textContent)")
        faux(opts == ['Jules F'], f'modifier la vente de Jules : vendeur choisi {opts}')
        opts = page.evaluate("[...document.getElementById('v-vendeur').options].map(o => o.textContent)")
        faux('Nour H' not in opts, 'Nour proposée dans la vente de Jules')
        page.evaluate("closeModal('vente')")
        # Remettre dans l'équipe
        page.evaluate("goTo('vendeurs', null); vendeurRemettre('v2')")
        page.wait_for_timeout(200)
        faux(page.locator('#vendeur-grid .vendeur-card', has_text='Jules').count() == 1, 'Jules pas revenu après « Remettre dans l’équipe »')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
