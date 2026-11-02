# Test de la rubrique Reporting : chiffres lus dans reporting_mois, vue Équipe, vue Cas par cas,
# points forts et sujets déduits des chiffres, commercial inactif écarté. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/reporting.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def v(nom, recus, tr, trg, pool, env, ech, coh, **k):
    d = {'v': nom, 'recus': recus, 'tr': tr, 'trg': trg, 'pool': pool, 'env': env, 'ech': ech, 'coh': coh,
         'cal': {'2026-10-01': 32, '2026-10-05': 73, '2026-10-06': 58, '2026-10-19': 0}, 'jours_actifs': 3, 'actions': 163, 'clients': 100, 'ess': 100, 'app': 70,
         'selections': {'env': 40, 'clients': 30, 'ouv': 34, 'reac': 8}, 'rdv_mois': 20, 'ventes': 0, 'hono': 0, 'vus': 20, 'suite7': 19, 'sans_suite': 0, 'vus_veille': 2,
         'pf': {'actifs': 100, 'retards': 2, 'sr': 40, 'sr0': 0, 'fin': 1, 'fin7': 1, 'rd': 10, 'rd7': 3, 'pat7': 5, 'veille': 9}}
    d.update(k)
    return d
def coh(ent, joints, sel, rdv, av, ve, cl, zero, j1, j2, j3, oub, t, dn, dj, tn=0, tj=0, pn=0, pj=0, delai=None):
    return dict(ent=ent, joints=joints, sel=sel, rdv=rdv, av=av, ve=ve, cl=cl, zero=zero, j1=j1, j2=j2, j3=j3, oub=oub, touche24=t, dir_n=dn, dir_j=dj, tr_n=tn, tr_j=tj, pool_n=pn, pool_j=pj, delai2=delai)
DONNEES = {'debut': '2026-09-30T22:00:00Z', 'fin': '2026-10-31T23:00:00Z', 'coupure': '2026-10-26T00:00:00+01:00', 'calcule_le': '2026-11-02T14:05:00Z', 'vendeurs': [
    v('Anais', 146, 42, 40, 22, 4, 27, coh(157, 56, 31, 33, 24, 3, 7, 30, 58, 5, 1, 73, 105, 113, 48, 27, 6, 17, 2), ventes=3, hono=12000, sans_suite=37, vus=77, suite7=60,
      pf={'actifs': 355, 'retards': 101, 'sr': 187, 'sr0': 28, 'fin': 0, 'fin7': 0, 'rd': 58, 'rd7': 48, 'pat7': 57, 'veille': 44}),
    v('Jules', 67, 28, 25, 60, 1, 6, coh(131, 44, 35, 25, 20, 0, 5, 14, 40, 20, 8, 51, 73, 57, 31, 19, 8, 55, 5, 4.1), vus=54, suite7=52),
    v('Nour', 0, 0, 0, 0, 0, 17, {}, actions=0, cal={}, clients=0, ess=0, app=0, selections={'env': 0, 'clients': 0, 'ouv': 0, 'reac': 0}),
    v('Madina', 37, 43, 41, 20, 5, 0, coh(78, 54, 28, 16, 4, 0, 4, 8, 9, 3, 0, 9, 59, 29, 22, 29, 21, 20, 11)),
]}

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        appels = []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if 'rpc/reporting_mois' in r.request.url:
                appels.append(json.loads(r.request.post_data))
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(DONNEES))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""() => { _hideLogin(); document.querySelectorAll('.page').forEach(x => x.classList.remove('active'));
            document.getElementById('page-reporting').classList.add('active');
            const m = document.getElementById('rp-mois'); rpInit(); m.value = '2026-10-01'; return rpCharger(); }""")
        page.wait_for_selector('.rp')
        if not appels or appels[-1].get('p_mois') != '2026-10-01': erreurs.append(f'{nom} : mois demandé : {appels}')
        if 'reporting' not in page.evaluate("PAGES_GERANT"): erreurs.append('page non réservée aux gérants')

        # Équipe : totaux, tableau, Nour écarté, retards individuels absents
        t = page.inner_text('#rp-corps')
        for a in ('250', 'leads reçus', 'LES MEILLEURS DU MOIS', 'Anaïs', 'LE MOIS DE CHACUN', '12 000 €'):
            if a.replace(' ', '') not in t.replace(' ', '').replace(' ', '').replace('\xa0', ''): erreurs.append(f'{nom} : équipe, absent : {a}')
        if 'Nour' in t: erreurs.append(f'{nom} : commercial inactif affiché')
        if 'retards sur' in t: erreurs.append(f'{nom} : retards individuels visibles en équipe')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : équipe déborde')
        page.screenshot(path=str(SORTIE / f'reporting_equipe_{nom}.png'), full_page=True)

        # Cas par cas : Anaïs, puis Jules
        page.evaluate("rpVue('perso')")
        opts = page.evaluate("[...document.getElementById('rp-vendeur').options].map(o => o.textContent)")
        if opts != ['Anaïs', 'Jules', 'Madina']: erreurs.append(f'{nom} : liste : {opts}')
        t = page.inner_text('#rp-corps')
        for a in ('146', 'N°1 sur les ventes', 'Rappeler au-delà du premier jour', 'Ne pas laisser filer les clients vus', '73', 'leads sans nouvelle'):
            if a not in t: erreurs.append(f'{nom} : Anaïs, absent : {a}')
        page.select_option('#rp-vendeur', 'Jules')
        t = page.inner_text('#rp-corps')
        for a in ('N°1 de la relance', 'N°1 du pool', 'Aucun client vu laissé sans suite', 'Aller chercher la vente', '4 jours après'):
            if a not in t: erreurs.append(f'{nom} : Jules, absent : {a}')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : cas par cas déborde')
        if page.evaluate("document.querySelectorAll('.rp-cal > div').length") != 7 + 3 + 31: erreurs.append(f'{nom} : calendrier')
        page.screenshot(path=str(SORTIE / f'reporting_perso_{nom}.png'), full_page=True)
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon')
sys.exit(1 if erreurs else 0)
