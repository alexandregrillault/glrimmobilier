# Remise sur tout un programme (demande d'Alex du 10/11/2026) : posée une fois sur
# l'en-tête du programme, elle est recopiée sur chacun de ses lots, à la composition
# comme sur une sélection déjà envoyée, et la feuille du client l'affiche sous chaque lot.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/selection_remise_programme.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
FEUILLE = ICI.parent.parent / 'glr-site' / 'selection' / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def lot(prog, num, ville='Bondy', prix='289 000 €'):
    return {'titre': f'{prog} — Lot {num}', 'programme': prog, 'ville': ville, 'promoteur': 'Promoteur test',
            'prix': prix, 'surface': '62 m²', 'typologies': ['T3'], 'remises': [], 'docs': []}

BIENS = [lot('Les Jardins', 'A101'), lot('Les Jardins', 'B204'), lot('Le Belvédère', 'C12', 'Pantin')]
BIENS[0]['remises'] = [{'libelle': 'Cuisine équipée offerte', 'montant': None}]
LEAD = {'id': 'c1', 'nom': 'Durand', 'prenom': 'Paul', 'statut': 'Sélections', 'vendeur': 'Louis', 'date_lead': '2026-11-01', 'activites': []}
SEL = {'token': 's1', 'contact_id': 'c1', 'created_at': '2026-11-05T09:00:00Z', 'opened_at': '2026-11-05T10:00:00Z',
       'expires_at': None, 'avis': {}, 'biens': BIENS, 'temps': {}, 'visites': 1, 'dernier_vu': None, 'maj_at': None, 'vendeur': 'Louis'}

erreurs = []
def verifier(cond, msg):
    if not cond: erreurs.append(msg)

with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e, nom=nom: erreurs.append(f'{nom} : {e}'))
        patchs = []
        def route(r, *_):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if r.request.method == 'PATCH' and '/selections' in r.request.url: patchs.append(json.loads(r.request.post_data))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', route)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if not x.endswith(': ok')]

        # ---- 1. Composition : remise programme, propagée à un lot ajouté ensuite
        page.evaluate("""([l, b]) => { _hideLogin();
            const d = document.createElement('div'); d.id = 'bloc-test';
            d.style.cssText = 'position:fixed;inset:0;z-index:1500;background:#fff;padding:16px;overflow:auto';
            d.innerHTML = '<div id="sel-libres"></div>'; document.body.appendChild(d);
            _selCtx = { lead: l, libres: JSON.parse(JSON.stringify(b.slice(0, 2))) }; selAjouterLibreRefresh(); }""", [LEAD, BIENS])
        t = page.inner_text('#sel-libres')
        verifier('Remise programme' in t, f'{nom} : bouton « Remise programme » absent de la composition : {t}')
        page.evaluate("selRemiseProgramme(0)")
        page.fill('#sel-remise-lib', 'Remise promoteur')
        page.fill('#sel-remise-montant', '8 000')
        page.click('text=Appliquer à tous les lots')
        page.evaluate("document.getElementById('sel-remise-modal').remove()")
        rs = page.evaluate("_selCtx.libres.map(b => b.remises)")
        verifier(all(any(r.get('programme') and r['montant'] == 8000 for r in x) for x in rs), f'{nom} : remise absente d\'un lot : {rs}')
        verifier(any(r['libelle'] == 'Cuisine équipée offerte' for r in rs[0]), f'{nom} : la remise propre au lot A101 a disparu')
        # Un 3e lot du même programme, ajouté après coup, la reçoit
        page.evaluate("""() => { const n = JSON.parse(JSON.stringify(_selCtx.libres[1])); n.titre = 'Les Jardins — Lot D301'; n.remises = [];
            _selCtx.libres.push(n); selAjouterLibreRefresh(); }""")
        rs = page.evaluate("_selCtx.libres.map(b => b.remises.filter(r => r.programme).length)")
        verifier(rs == [1, 1, 1], f'{nom} : propagation au lot ajouté : {rs}')
        # Rouvrir un lot avec ✎ ne doit ni perdre ni doubler la remise programme
        page.screenshot(path=str(SORTIE / f'remise_programme_composition_{nom}.png'))
        # Retrait depuis le programme : enlevée de tous les lots, la remise du lot reste
        page.evaluate("selRemiseProgrammeRetirer(0, 0); document.getElementById('sel-remise-modal')?.remove()")
        rs = page.evaluate("_selCtx.libres.map(b => b.remises.length)")
        verifier(rs == [1, 0, 0], f'{nom} : retrait de la remise programme : {rs}')
        page.evaluate("document.getElementById('bloc-test').remove()")

        # ---- 2. Fiche client, sélection déjà envoyée
        page.evaluate("""([l, s]) => { _eqLeads = [l]; _eqSelectionsAll = [s]; _eqSelections = { c1: s }; }""", [LEAD, SEL])
        page.evaluate("""() => { const d = document.createElement('div'); d.id = 'bloc-test';
            d.style.cssText = 'position:fixed;inset:0;z-index:1500;background:#fff;padding:16px;overflow:auto';
            d.innerHTML = eqFicheSelectionsHtml(_eqLeads[0]); document.body.appendChild(d); }""")
        t = page.inner_text('#bloc-test')
        verifier(t.count('+ Remise programme') == 2, f'{nom} : {t.count("+ Remise programme")} boutons « Remise programme » au lieu de 2')
        page.evaluate("eqRemiseProgrammeOuvrir('s1', '0-1')")
        verifier('2 lots' in page.inner_text('#eq-remise-modal'), f'{nom} : la fenêtre ne dit pas « 2 lots »')
        page.fill('#eq-remise-lib', 'Frais de notaire offerts')
        page.click('text=Appliquer à tous les lots')
        page.wait_for_timeout(300)
        verifier(len(patchs) == 1, f'{nom} : {len(patchs)} enregistrements au lieu de 1')
        if patchs:
            b = patchs[0]['biens']
            verifier(all(any(r['libelle'] == 'Frais de notaire offerts' and r.get('programme') for r in x['remises']) for x in b[:2]),
                     f'{nom} : remise absente des lots des Jardins : {b}')
            verifier(not b[2]['remises'], f'{nom} : la remise a touché un autre programme : {b[2]}')
        page.evaluate("""() => { document.getElementById('bloc-test').innerHTML = eqFicheSelectionsHtml(_eqLeads[0]); }""")
        page.screenshot(path=str(SORTIE / f'remise_programme_fiche_{nom}.png'))
        t = page.inner_text('#bloc-test')
        verifier(t.count('Frais de notaire offerts') == 1, f'{nom} : la remise programme doit apparaître une fois (en-tête), pas sous chaque lot')
        page.evaluate("eqRemiseProgrammeRetirer('s1', '0-1', 0)")
        page.wait_for_timeout(300)
        if len(patchs) == 2:
            verifier(not any(r.get('programme') for x in patchs[1]['biens'] for r in x['remises']), f'{nom} : retrait incomplet')
        else:
            erreurs.append(f'{nom} : retrait non enregistré')
        if nom == 'iphone':
            verifier(not page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"), 'iphone : la fiche déborde en largeur')
        page.close()

        # ---- 3. Feuille du client : la remise sous chaque lot
        feuille = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        feuille.on('pageerror', lambda e, nom=nom: erreurs.append(f'{nom} feuille : {e}'))
        biens_client = json.loads(json.dumps(BIENS))
        for x in biens_client[:2]: x['remises'].append({'libelle': 'Remise promoteur', 'montant': 8000, 'programme': True})
        donnees = {'ok': True, 'vendeur': 'Louis', 'client': 'Paul', 'biens': biens_client, 'avis': {}}
        feuille.route('**/*', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(donnees))
                      if 'supabase.co' in r.request.url else r.continue_())
        feuille.goto(FEUILLE.as_uri() + '?t=s1&apercu=1')
        feuille.wait_for_timeout(1500)
        n = feuille.evaluate("document.querySelectorAll('.lot-row .remise').length")
        offres = feuille.evaluate("[...document.querySelectorAll('.lot-row')].map(r => [...r.querySelectorAll('.remise')].map(x => x.innerText.replace(/\\s+/g, ' ')))")
        verifier(sum('Remise promoteur' in ' '.join(o) for o in offres) == 2, f'{nom} feuille : remise programme pas sous chacun des 2 lots : {offres}')
        el = feuille.query_selector('.lot-row .remise')
        if el: el.scroll_into_view_if_needed()
        feuille.screenshot(path=str(SORTIE / f'remise_programme_feuille_{nom}.png'))
        feuille.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
