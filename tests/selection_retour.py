# Test du retour d'un client sur sa sélection : dernier passage dans la fiche, date à côté du
# nom dans les activités et sur le badge du tableau. Pas de date tant qu'il n'y a qu'une visite.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/selection_retour.py [dossier des captures]
import datetime, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

AUJ = datetime.date.today().isoformat()
def lead(i, nom, act):
    return {'id': i, 'nom': nom, 'prenom': '', 'statut': 'Retour documentation', 'vendeur': 'Louis', 'date_lead': '2026-10-01',
            'activites': [{'id': act, 'le': AUJ, 'titre': 'Le client est revenu sur sa sélection (dernière visite il y a 4 jours)', 'heure': None, 'systeme': True}] if act else []}
LEADS = [lead('c1', 'Durand Retour', 'retour_client'), lead('c2', 'Martin Reaction', 'reaction_client'), lead('c3', 'Petit Premiere', 'reaction_client')]
LEADS[1]['activites'][0]['reactions'] = ['interesse']
LEADS[2]['activites'][0]['reactions'] = ['interesse']
def sel(t, c, v, vu):
    return {'token': t, 'contact_id': c, 'created_at': '2026-10-01T09:00:00Z', 'opened_at': '2026-10-01T10:00:00Z', 'expires_at': None,
            'avis': {}, 'biens': [], 'temps': {}, 'visites': v, 'dernier_vu': vu, 'maj_at': None}
SELECTIONS = [
    sel('s1', 'c1', 3, '2026-11-02T10:53:00Z'),
    sel('s1b', 'c1', 2, '2026-10-20T08:00:00Z'),      # plus ancienne : c'est s1 qui doit l'emporter
    sel('s2', 'c2', 2, '2026-10-31T17:05:00Z'),
    sel('s3', 'c3', 1, '2026-10-30T12:00:00Z'),       # une seule visite : ce n'est pas un retour
]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        page.route('**/*', lambda r: r.continue_() if 'supabase.co' not in r.request.url
                   else r.fulfill(status=200, content_type='application/json', body='[]'))
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""([ls, ss]) => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = ss;
            _eqSelections = {}; ss.forEach(s => { if (!_eqSelections[s.contact_id]) _eqSelections[s.contact_id] = s; }); }""", [LEADS, SELECTIONS])

        # Calcul : la visite la plus récente, jamais une première ouverture
        r = page.evaluate("() => _eqLeads.map(eqDernierPassageTxt)")
        if r != ['02/11 à 11h53', '31/10 à 18h05', '']: erreurs.append(f'{nom} : dates inattendues : {r}')

        # Activités : la date à côté du nom
        page.evaluate("renderEqNotifs()")
        t = page.evaluate("() => document.getElementById('eq-notif-liste').innerText")
        if 'Durand Retour revenu le 02/11 à 11h53' not in t: erreurs.append(f'{nom} : date absente des activités : {t}')
        if 'Martin Reaction revenu le 31/10 à 18h05' not in t: erreurs.append(f'{nom} : date absente pour une réaction : {t}')
        if 'Petit Premiere revenu' in t: erreurs.append(f'{nom} : première visite présentée comme un retour')
        page.evaluate("document.getElementById('eq-notif-liste').style.display = 'block'; document.getElementById('eq-notif-liste').scrollIntoView()")
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1") and nom == 'iphone':
            erreurs.append('iphone : la page déborde en largeur')

        # Fiche : le dernier passage sélection par sélection
        h = page.evaluate("""() => { const d = document.createElement('div'); d.id = 'bloc-test';
            d.style.cssText = 'position:fixed;inset:0;z-index:9999;background:#fff;padding:16px;overflow:auto';
            d.innerHTML = _eqLeads.map(eqFicheSelectionsHtml).join(''); document.body.appendChild(d); return d.innerText; }""")
        if 'dernier passage le 02/11/2026 à 11h53' not in h: erreurs.append(f'{nom} : dernier passage absent de la fiche : {h}')
        if h.count('dernier passage') != 3: erreurs.append(f'{nom} : {h.count("dernier passage")} passages au lieu de 3 (s3 ne doit pas en avoir)')
        page.screenshot(path=str(SORTIE / f'selection_retour_fiche_{nom}.png'))
        page.evaluate("document.getElementById('bloc-test').remove()")

        # Tableau des leads : le badge
        page.evaluate("renderEquipeLeadsTable()")
        b = page.evaluate("() => document.getElementById('eq-leads-tbody').textContent")
        if 'Revenu le 02/11 à 11h53' not in b: erreurs.append(f'{nom} : date absente du badge retour : {b[:300]}')
        if 'revenu le 31/10 à 18h05' not in b: erreurs.append(f'{nom} : date absente du badge réaction : {b[:300]}')

        # Capture des activités, seules à l'écran
        page.evaluate("""() => { const b = document.createElement('div'); b.id = 'bloc-test';
            b.style.cssText = 'position:fixed;inset:0;z-index:9999;background:#fff;padding:16px;overflow:auto';
            b.innerHTML = document.getElementById('eq-notif-liste').innerHTML; document.body.appendChild(b); }""")
        page.screenshot(path=str(SORTIE / f'selection_retour_activites_{nom}.png'))
        page.evaluate("document.getElementById('bloc-test').remove()")
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon')
sys.exit(1 if erreurs else 0)
