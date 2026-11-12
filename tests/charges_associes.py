# Test des charges des associés (demande d'Alex du 12/11/2026) : sous Théophile et Alexandre,
# seulement « Salaire », « Remboursement CCA » et « Dépenses carte » ; une dépense carte rangée
# vers l'un d'eux va dans « Dépenses carte » avec le commerçant en détail ; la section Société
# garde sa liste ; la charge fixe « Salaires » s'affiche. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/charges_associes.py [dossier des captures]
import pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

CHARGES = [
    {'id': 'c1', 'libelle': 'Salaire', 'categorie': 'variable', 'sousSection': 'theo', 'mois': '2026-10', 'montant': 2000, 'recurrence': 'unique', 'taxe': None},
    {'id': 'c2', 'libelle': 'Dépenses carte', 'marchand': 'DECATHLON WAGRAM', 'categorie': 'variable', 'sousSection': 'theo', 'mois': '2026-10', 'montant': 186.97, 'recurrence': 'unique', 'taxe': None},
]
FIXES = [{'id': 'cf-salaires', 'libelle': 'Salaires', 'taxe': '', 'dateDebut': '2026-09', 'dateFin': None,
          'tranches': [{'mois': '2026-09', 'montant': 4000}, {'mois': '2026-10', 'montant': 4000}]}]
A_RANGER = [{'id': 'r1', 'date': '2026-10-12', 'marchand': 'BOLT TALLINN', 'carte': 'alex', 'montant': 14.4},
            {'id': 'r2', 'date': '2026-10-13', 'marchand': 'AMAZON', 'carte': 'societe', 'montant': 50}]

def route(r):
    if 'supabase.co' not in r.request.url: return r.continue_()
    return r.fulfill(status=200, content_type='application/json', body='[]')

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp)
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        page.evaluate("""([ch, cf, ar]) => { _hideLogin(); data.charges = JSON.parse(JSON.stringify(ch));
            data.chargesFixes = JSON.parse(JSON.stringify(cf)); data.aRanger = JSON.parse(JSON.stringify(ar)); }""", [CHARGES, FIXES, A_RANGER])
        opts = lambda: page.eval_on_selector_all('#c-libelle-select option', 'os => os.map(o => o.value)')
        page.evaluate("openModalVariableFor('alex')")
        if opts() != ['Salaire', 'Remboursement CCA', 'Dépenses carte']: erreurs.append(f'{nom} : rubriques Alexandre {opts()}')
        page.evaluate("closeModal('charge')")
        page.evaluate("openModalVariableFor('societe')")
        if 'Autre' not in opts() or 'Dépense perso' not in opts(): erreurs.append(f'{nom} : rubriques Société {opts()}')
        page.evaluate("closeModal('charge')")
        page.evaluate("openEditCharge('c2')")
        if page.input_value('#c-libelle-select') != 'Dépenses carte': erreurs.append(f'{nom} : modification d’une dépense carte')
        page.evaluate("closeModal('charge')")
        page.evaluate("assignARanger('r1', 'alex'); assignARanger('r2', 'commun')")
        ranges = page.evaluate("data.charges.filter(c => c.id !== 'c1' && c.id !== 'c2').map(c => [c.sousSection, c.libelle, c.marchand])")
        if ['alex', 'Dépenses carte', 'BOLT TALLINN'] not in ranges: erreurs.append(f'{nom} : rangement vers Alexandre {ranges}')
        if ['societe', 'AMAZON', 'AMAZON'] not in ranges: erreurs.append(f'{nom} : rangement vers la Société {ranges}')
        page.evaluate("goTo('charges', null)")
        page.wait_for_timeout(300)
        page.evaluate("currentPeriod = 'tout'; renderCharges()")
        if 'Salaires' not in page.inner_text('#tbody-fixe'): erreurs.append(f'{nom} : ligne Salaires absente des charges fixes')
        page.evaluate("document.querySelectorAll('#tbody-var-theo .cv-group-head').forEach(h => h.click())")
        if 'DECATHLON WAGRAM' not in page.inner_text('#tbody-var-theo'): erreurs.append(f'{nom} : commerçant absent du détail')
        page.screenshot(path=str(SORTIE / f'charges_associes_{nom}.png'), full_page=False)
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
