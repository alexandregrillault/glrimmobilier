# Test des dénonciations dans le CRM (demande d'Alex du 09/11/2026) : bloc « Dénonciations » de la
# fiche client (un état par programme, le meilleur quand il y a eu plusieurs tentatives) et pastille
# sur chaque lot à la composition d'une sélection, avec le résumé qui prévient sans bloquer l'envoi.
# Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/denonciations.py [dossier des captures]
import json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

LEADS = [{'id': 'c1', 'nom': 'Client Test', 'prenom': '', 'statut': 'Suivi', 'vendeur': 'Louis', 'date_lead': '2026-11-09',
          'lieu': 'Aubervilliers (93300)', 'appels': []}]
DENONC = [
    {'compte': 'care', 'promoteur': 'CARE PROMOTION', 'programme': 'Stand Up', 'ville': 'Aubervilliers', 'statut': 'envoyee', 'fait_le': '2026-11-09T15:14:00+00:00'},
    {'compte': 'care', 'promoteur': 'CARE PROMOTION', 'programme': 'Stand Up', 'ville': 'Aubervilliers', 'statut': 'echec', 'fait_le': '2026-11-09T14:14:00+00:00', 'detail': 'essai raté'},
    {'compte': 'wemo', 'promoteur': 'wemo', 'programme': 'Icone', 'ville': 'Aubervilliers', 'statut': 'deja_connu', 'fait_le': '2026-11-09T15:20:00+00:00', 'detail': 'Refus du promoteur'},
    {'compte': 'logih', 'promoteur': 'LOGI H', 'programme': "Le Jardin d'Hélène", 'ville': 'Aubervilliers', 'statut': 'acceptee', 'fait_le': '2026-11-09T15:30:00+00:00'},
]
BIENS = [
    {'titre': 'Stand Up — lot A12', 'programme': 'Stand Up', 'ville': 'Aubervilliers', 'prix': '250 000 €'},
    {'titre': 'Icone — lot 3', 'programme': 'Icone (93)', 'ville': 'Aubervilliers', 'prix': '260 000 €'},
    {'titre': 'Passage Des Arts — lot 7', 'programme': 'Passage Des Arts', 'ville': 'Aubervilliers', 'prix': '270 000 €'},
]

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        lus = []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if '/rest/v1/denonciations' in r.request.url:
                lus.append(r.request.url)
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(DENONC))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        page.evaluate("ls => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = []; _eqSelections = {}; }", LEADS)

        # 1. Fiche : un état par programme, le meilleur l'emporte (envoyée plutôt qu'échec)
        page.evaluate("eqOuvrirFiche('c1')")
        page.wait_for_function("document.getElementById('eq-fiche-corps') && document.getElementById('eq-fiche-corps').innerText.includes('DÉNONCIATIONS') || (document.getElementById('eq-fiche-corps')||{innerText:''}).innerText.toLowerCase().includes('dénonciations')", timeout=5000)
        txt = page.inner_text('#eq-fiche-corps')
        for attendu in ('Stand Up', 'Dénoncé le 09/11', 'Déjà connu du promoteur', 'pris en charge', '2 dénoncés · 1 déjà connu'):
            if attendu not in txt: erreurs.append(f'{nom} : fiche sans « {attendu} »')
        if 'Pas encore dénoncé' in txt: erreurs.append(f'{nom} : l\'échec de Stand Up l\'emporte sur l\'envoi')
        if not lus or 'statut=neq.essai' not in lus[0] or 'contact_id=eq.c1' not in lus[0]: erreurs.append(f'{nom} : lecture du registre : {lus[:1]}')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : fiche déborde en largeur')
        page.screenshot(path=str(SORTIE / f'denonciations_fiche_{nom}.png'), full_page=True)
        page.evaluate("eqFicheFermer()")

        # 2. Sélection : pastille sur chaque lot, résumé qui prévient sans bloquer
        page.evaluate("eqOuvrirSelection('c1')")
        page.wait_for_selector('#eq-sel-modal')
        page.evaluate("bs => { _selCtx.libres = bs; selAjouterLibreRefresh(); }", BIENS)
        page.wait_for_function("document.getElementById('sel-libres').innerText.includes('Dénoncé le')", timeout=5000)
        lots = page.inner_text('#sel-libres')
        for attendu in ('Dénoncé le 09/11', 'Déjà connu du promoteur', 'Pas encore dénoncé'):
            if attendu not in lots: erreurs.append(f'{nom} : lots sans « {attendu} »')
        resume = page.inner_text('#sel-denonc-resume')
        if 'Programme pas encore dénoncé : Passage Des Arts' not in resume: erreurs.append(f'{nom} : résumé manquants : {resume!r}')
        if 'Déjà connu du promoteur, commission non garantie : Icone' not in resume: erreurs.append(f'{nom} : résumé déjà connu : {resume!r}')
        if 'envoi reste possible' not in resume: erreurs.append(f'{nom} : le résumé ne dit pas que l\'envoi reste possible')
        if page.is_disabled('#sel-btn-valider'): erreurs.append(f'{nom} : bouton d\'envoi bloqué')
        page.evaluate("() => { const r = document.getElementById('sel-denonc-resume'); if (r) r.scrollIntoView(); }")
        page.screenshot(path=str(SORTIE / f'denonciations_selection_{nom}.png'))
        # Tout dénoncé : message positif
        page.evaluate("bs => { _selCtx.libres = bs.slice(0, 1); selAjouterLibreRefresh(); }", BIENS)
        if 'Tous les programmes de cette sélection sont dénoncés' not in page.inner_text('#sel-denonc-resume'): erreurs.append(f'{nom} : message « tous dénoncés » absent')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Dénonciations : tout est bon (bureau et iPhone).')
sys.exit(1 if erreurs else 0)
