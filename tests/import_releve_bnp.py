# Test de l'import du relevé BNP (demande d'Alex du 11/11/2026) :
# - virement « SALAIRE » : proposition = charge fixe « Salaires » jusqu'à 2 000 € par associé et par mois,
#   le dépassement en ligne « Salaire » dans la section de l'associé, montant du mois AJOUTÉ ;
#   Alex peut choisir ligne par ligne « tout en fixe » ou « tout en variable » ;
# - virement « FACTURE PRESTATION » → charge « commission », commercial choisi dans l'aperçu.
# Bureau et iPhone. Lancer : ~/glr-pige-robot/.venv/bin/python tests/import_releve_bnp.py [dossier des captures]
import pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

VENDEURS = [
    {'id': 'alex001', 'prenom': 'Alexandre', 'nom': 'Grillault'},
    {'id': 'theo001', 'prenom': 'Théophile', 'nom': 'Rouyer'},
    {'id': 'v-anais', 'prenom': 'Anais', 'nom': 'Mellan'},
    {'id': 'v-louis', 'prenom': 'Louis', 'nom': 'Grillault'},
]
# Octobre saisi à la main (sans détail) ; novembre : 1 500 € d'Alex déjà importés.
FIXES = [{'id': 'cf-salaires', 'libelle': 'Salaires', 'taxe': '', 'dateDebut': '2026-09', 'dateFin': None,
          'tranches': [{'mois': '2026-10', 'montant': 4000},
                       {'mois': '2026-11', 'montant': 1500, 'detail': {'alex': 1500}}]}]
OPS = [
    ('2026-11-05', 'VIR SEPA EMIS /MOTIF SALAIRE NOVEMBRE /BEN ALEXANDRE GRILLAULT', -1000),
    ('2026-11-05', 'VIR SEPA EMIS /MOTIF SALAIRE NOVEMBRE /BEN THEOPHILE ROUYER', -2500),
    ('2026-11-20', 'VIR SEPA EMIS /MOTIF SALAIRE COMPLEMENT /BEN M DUPONT', -800),
    ('2026-11-10', 'VIR SEPA EMIS /MOTIF FACTURE PRESTATION OCTOBRE /BEN ANAIS MELLAN', -3000),
    ('2026-11-12', 'VIR SEPA EMIS /MOTIF FACTURE PRESTATION 12 /BEN SARL XYZ', -1200),
    ('2026-10-28', 'VIR SEPA EMIS /MOTIF SALAIRE OCTOBRE /BEN ALEXANDRE GRILLAULT', -2000),
]

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
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""([vd, cf, ops]) => {
            _hideLogin(); data.vendeurs = vd; data.chargesFixes = JSON.parse(JSON.stringify(cf)); data.charges = []; data.aRanger = [];
            openImportReleve();
            IMPORT = { meta: {}, lignes: ops.map(([date, lib, m]) => {
                const op = bnpEnrich({ date, section: '', libelleBrut: lib, montant: m, sens: 'debit' });
                const v = bnpVentiler(op);
                return { op, v, doublon: false, garder: v.dest !== 'exclu' };
            }) };
            renderImportApercu();
        }""", [VENDEURS, FIXES, OPS])

        v = page.evaluate("() => IMPORT.lignes.map(l => l.v)")
        attendu = [('salaire', 'alex'), ('salaire', 'theo'), ('salaire', None), ('commission', 'v-anais'), ('commission', ''), ('salaire', 'alex')]
        for i, (dest, qui) in enumerate(attendu):
            got = (v[i].get('dest'), v[i].get('associe') if dest == 'salaire' else v[i].get('vendeurId'))
            if got != (dest, qui): erreurs.append(f'{nom} : ligne {i} classée {got} au lieu de {(dest, qui)}')

        txt = page.text_content('#import-apercu').replace(' ', ' ').replace('\xa0', ' ')
        if '10/2026 vaut déjà 4 000,00 €' not in txt: erreurs.append(f'{nom} : avertissement octobre absent')

        # Associé et commercial manquants : l'enregistrement est refusé
        page.evaluate("validerImportReleve()")
        if page.evaluate("data.charges.length") != 0: erreurs.append(f'{nom} : enregistré malgré un associé manquant')
        page.locator('select.imp-associe').nth(2).select_option('theo')
        page.evaluate("validerImportReleve()")
        if page.evaluate("data.charges.length") != 0: erreurs.append(f'{nom} : enregistré malgré un commercial manquant')
        page.locator('select.imp-vendeur').nth(1).select_option('v-louis')

        # Proposition par défaut, puis les choix d'Alex sur deux lignes
        parts = page.evaluate("() => IMPORT.lignes.map(l => [l.v.partFixe ?? null, l.v.partVar ?? null])")
        if parts[0] != [500, 500]: erreurs.append(f'{nom} : proposition Alex novembre {parts[0]} au lieu de 500 + 500')
        if parts[2] != [0, 800]: erreurs.append(f'{nom} : proposition complément Théo {parts[2]} au lieu de 0 + 800')
        page.locator('select.imp-sal-choix').nth(0).select_option('variable')
        page.locator('select.imp-sal-choix').nth(2).select_option('fixe')

        parts = page.evaluate("() => IMPORT.lignes.map(l => [l.v.partFixe ?? null, l.v.partVar ?? null])")
        if parts[0] != [0, 1000]: erreurs.append(f'{nom} : salaire Alex novembre (tout en variable) {parts[0]} au lieu de 0 + 1000')
        if parts[1] != [2000, 500]: erreurs.append(f'{nom} : salaire Théo réparti {parts[1]} au lieu de 2000 + 500')
        if parts[2] != [800, 0]: erreurs.append(f'{nom} : complément Théo (tout en fixe) {parts[2]} au lieu de 800 + 0')
        if parts[5] != [2000, 0]: erreurs.append(f'{nom} : salaire Alex octobre réparti {parts[5]} au lieu de 2000 + 0')

        page.locator('#import-apercu').scroll_into_view_if_needed()
        page.screenshot(path=str(SORTIE / f'import_releve_{nom}.png'), full_page=False)
        larg = page.evaluate("document.querySelector('#modal-import .modal') ? document.querySelector('#modal-import .modal').scrollWidth : 0")
        if nom == 'iphone' and larg > 400: erreurs.append(f'{nom} : fenêtre trop large ({larg} px)')

        page.evaluate("validerImportReleve()")
        page.wait_for_timeout(300)
        r = page.evaluate("""() => ({ tr: data.chargesFixes.find(x => x.id === 'cf-salaires').tranches,
            ch: data.charges.map(c => [c.libelle, c.categorie, c.sousSection, c.mois, c.montant, c.vendeurId || null]),
            emp: (data.objectifs.empreintesFixes || []).length })""")
        tr = {t['mois']: t for t in r['tr']}
        if tr['2026-11']['montant'] != 4300 or tr['2026-11'].get('detail') != {'alex': 1500, 'theo': 2800}:
            erreurs.append(f'{nom} : Salaires novembre {tr["2026-11"]} au lieu de 4300 (alex 1500, theo 2800)')
        if tr['2026-10']['montant'] != 6000 or tr['2026-10'].get('detail') != {'alex': 2000}:
            erreurs.append(f'{nom} : Salaires octobre {tr["2026-10"]} au lieu de 6000 ajoutés (alex 2000)')
        attendu_ch = sorted([
            ['Salaire', 'variable', 'alex', '2026-11', 1000, None],
            ['Salaire', 'variable', 'theo', '2026-11', 500, None],
            ['Commission Anais', 'commission', None, '2026-11', 3000, 'v-anais'],
            ['Commission Louis', 'commission', None, '2026-11', 1200, 'v-louis'],
        ], key=str)
        if sorted(r['ch'], key=str) != attendu_ch: erreurs.append(f'{nom} : charges enregistrées {r["ch"]}')
        if r['emp'] != 3: erreurs.append(f'{nom} : {r["emp"]} empreintes de salaires au lieu de 3')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
