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
          'lieu': 'Aubervilliers (93300)', 'appels': []},
         {'id': 'c2', 'nom': 'Georges Test', 'prenom': 'Georges', 'nom_famille': 'Test', 'civilite': None, 'statut': 'Suivi',
          'vendeur': 'Louis', 'date_lead': '2026-11-10', 'lieu': 'Colombes (92700)', 'appels': []}]
# Civilité (décision d'Alex du 10/11/2026) : le robot a dénoncé Georges chez iSelection en « Mme »
# (cas d'erreur simulé) ; le vendeur confirme « M. » → bandeau d'alerte, puis « C'est corrigé ».
# Fiche incomplète (décision d'Alex du 10/11/2026) : Morgane n'a pas de nom de famille ni de civilité
LEADS.append({'id': 'c3', 'nom': 'Morgane', 'prenom': 'Morgane', 'statut': 'Nouveau', 'vendeur': 'Louis',
              'date_lead': '2026-11-10', 'lieu': 'Ivry-sur-Seine (94200)', 'appels': []})
# Nom tiré de l'e-mail : c4 à valider, c5 dénoncé sous un nom que la fiche contredit maintenant
LEADS.append({'id': 'c4', 'nom': 'Morgane', 'prenom': 'Morgane', 'statut': 'Nouveau', 'vendeur': 'Louis', 'email': 'morgane.lafagne@exemple.fr',
              'date_lead': '2026-11-10', 'lieu': 'Ivry-sur-Seine (94200)', 'appels': []})
LEADS.append({'id': 'c5', 'nom': 'Morgane Lafargue', 'prenom': 'Morgane', 'nom_famille': 'Lafargue', 'statut': 'Suivi', 'vendeur': 'Louis',
              'date_lead': '2026-11-10', 'lieu': 'Ivry-sur-Seine (94200)', 'appels': []})
DENONC_C2 = [{'plateforme': 'iselection', 'compte': 'iselection', 'promoteur': 'ISELECTION', 'programme': 'Opus', 'ville': 'Colombes',
              'statut': 'envoyee', 'fait_le': '2026-11-10T10:00:00+00:00', 'civilite': 'Mme'}]
DENONC = [
    {'compte': 'care', 'promoteur': 'CARE PROMOTION', 'programme': 'Stand Up', 'ville': 'Aubervilliers', 'statut': 'envoyee', 'fait_le': '2026-11-09T15:14:00+00:00',
     'nom_promoteur': 'Client Test', 'nom_verif': 'ok', 'nom_verifie_le': '2026-11-10T19:30:00+00:00'},
    {'compte': 'care', 'promoteur': 'CARE PROMOTION', 'programme': 'Stand Up', 'ville': 'Aubervilliers', 'statut': 'echec', 'fait_le': '2026-11-09T14:14:00+00:00', 'detail': 'essai raté'},
    {'compte': 'wemo', 'promoteur': 'wemo', 'programme': 'Icone', 'ville': 'Aubervilliers', 'statut': 'deja_connu', 'fait_le': '2026-11-09T15:20:00+00:00', 'detail': 'Refus du promoteur'},
    {'compte': 'logih', 'promoteur': 'LOGI H', 'programme': "Le Jardin d'Hélène", 'ville': 'Aubervilliers', 'statut': 'acceptee', 'fait_le': '2026-11-09T15:30:00+00:00',
     'nom_promoteur': 'CLIENT', 'nom_verif': 'different', 'nom_verifie_le': '2026-11-10T19:30:00+00:00'},
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
        lus, appels = [], []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if '/rest/v1/denonciations' in r.request.url:
                lus.append(r.request.url)
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(DENONC_C2 if 'eq.c2' in r.request.url else DENONC))
            if '/rpc/denonciation_manques' in r.request.url:
                corps = r.request.post_data or ''
                c3 = 'c3' in corps
                rep = {'manque': ['nom', 'civilite'] if c3 else [], 'programmes': 3 if c3 else 0}
                if 'c4' in corps:
                    valide = any(m == 'PATCH' and 'Lafagne' in (d or '') for m, u, d in appels)
                    rep = {'manque': [], 'programmes': 3, 'identite': {'prenom': 'Morgane', 'nom': 'Lafagne', 'source': 'fiche' if valide else 'email'}}
                if 'c5' in corps and not any('denonciation_nom_corrige' in u for m, u, d in appels):
                    rep = {'manque': [], 'programmes': 3, 'identite': {'prenom': 'Morgane', 'nom': 'Lafargue', 'source': 'fiche'},
                           'ecart_nom': {'nom': 'Morgane Lafagne', 'promoteurs': ['CARE PROMOTION', 'BOUYGUES']}}
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(rep))
            if '/rpc/denonciation_relancer' in r.request.url:
                appels.append(('POST', r.request.url, r.request.post_data))
                n = sum(1 for a in appels if 'denonciation_relancer' in a[1])
                return r.fulfill(status=200, content_type='application/json',
                                 body=json.dumps({'manque': ['civilite'] if n == 1 else [], 'programmes': 3, 'relance': n > 1}))
            if '/rpc/civilite_du_prenom' in r.request.url:
                return r.fulfill(status=200, content_type='application/json', body='"M."')
            if '/rpc/denonciation_civilite_corrigee' in r.request.url or '/rpc/denonciation_nom_corrige' in r.request.url or '/rest/v1/contacts' in r.request.url and r.request.method == 'PATCH':
                appels.append((r.request.method, r.request.url, r.request.post_data))
                return r.fulfill(status=200, content_type='application/json', body='1' if 'rpc' in r.request.url else '[]')
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        page.evaluate("ls => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = []; _eqSelections = {}; }", LEADS)

        # 1. Fiche : un état par programme, le meilleur l'emporte (envoyée plutôt qu'échec)
        page.evaluate("eqOuvrirFiche('c1')")
        page.wait_for_function("document.getElementById('eq-fiche-corps') && document.getElementById('eq-fiche-corps').innerText.includes('DÉNONCIATIONS') || (document.getElementById('eq-fiche-corps')||{innerText:''}).innerText.toLowerCase().includes('dénonciations')", timeout=5000)
        txt = page.inner_text('#eq-fiche-corps')
        for attendu in ('Stand Up', 'Dénoncé le 09/11', 'Déjà connu du promoteur', 'pris en charge', '2 dénoncés · 1 déjà connu',
                        'Au nom de « Client Test », vérifié chez le promoteur le 10/11', 'Chez le promoteur : « CLIENT »'):
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
        page.evaluate("() => { const m = document.getElementById('eq-sel-modal'); if (m) m.remove(); }")

        # 3. Civilité : déduite du prénom (à confirmer), confirmation, alerte si iSelection a reçu l'autre
        page.evaluate("eqOuvrirFiche('c2')")
        page.wait_for_function("(document.getElementById('eq-fiche-corps')||{innerText:''}).innerText.includes('à confirmer')", timeout=5000)
        txt = page.inner_text('#eq-fiche-corps')
        if 'Civilité à corriger' in txt: erreurs.append(f'{nom} : alerte avant toute confirmation')
        page.click("#eq-fiche-corps button[onclick*=\"eqCiviliteSet('c2', 'Monsieur')\"]")
        page.wait_for_function("(document.getElementById('eq-fiche-corps')||{innerText:''}).innerText.includes('Civilité à corriger')", timeout=5000)
        if not any(m == 'PATCH' and 'Monsieur' in (d or '') for m, u, d in appels): erreurs.append(f'{nom} : civilité non enregistrée : {appels}')
        if page.evaluate("_eqLeads.find(x => x.id === 'c2').civilite") != 'Monsieur': erreurs.append(f'{nom} : civilité pas à jour sur la fiche')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : fiche civilité déborde en largeur')
        page.screenshot(path=str(SORTIE / f'denonciations_civilite_{nom}.png'))
        page.click("button:has-text(\"C'est corrigé\")")
        page.wait_for_timeout(500)
        if not any('denonciation_civilite_corrigee' in u and 'c2' in (d or '') for m, u, d in appels): erreurs.append(f'{nom} : « C\'est corrigé » non envoyé')
        page.evaluate("eqFicheFermer()")

        # 4. Fiche incomplète : carré rouge, « C'est fait » refusé tant qu'il manque, puis relance
        page.evaluate("eqOuvrirFiche('c3')")
        page.wait_for_selector('#eq-denonc-manque', timeout=5000)
        txt = page.inner_text('#eq-denonc-manque')
        for attendu in ('Dénonciations en attente (3 programmes)', 'nom de famille', 'civilité', "C'est fait"):
            if attendu not in txt: erreurs.append(f'{nom} : carré rouge sans « {attendu} » : {txt!r}')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : carré rouge déborde en largeur')
        page.screenshot(path=str(SORTIE / f'denonciations_manque_{nom}.png'))
        page.click("#eq-denonc-manque button")
        page.wait_for_timeout(400)
        if not page.query_selector('#eq-denonc-manque'): erreurs.append(f'{nom} : carré rouge retiré alors qu\'il manque encore la civilité')
        page.click("#eq-denonc-manque button")
        page.wait_for_timeout(400)
        if page.query_selector('#eq-denonc-manque'): erreurs.append(f'{nom} : carré rouge resté après la relance')
        if sum(1 for a in appels if 'denonciation_relancer' in a[1] and 'c3' in (a[2] or '')) != 2: erreurs.append(f'{nom} : relances : {appels}')
        page.evaluate("eqFicheFermer()")

        # 5. Nom tiré de l'e-mail : mis en avant, « C'est bon » l'écrit sur la fiche
        page.evaluate("eqOuvrirFiche('c4')")
        page.wait_for_selector('#eq-nom-retenu', timeout=5000)
        txt = page.inner_text('#eq-nom-retenu')
        for attendu in ('Morgane Lafagne', "e-mail", 'Prénom : Morgane', 'Nom : Lafagne', "C'est bon", 'Corriger'):
            if attendu not in txt: erreurs.append(f'{nom} : encadré nom retenu sans « {attendu} » : {txt!r}')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : encadré nom déborde')
        page.screenshot(path=str(SORTIE / f'denonciations_nom_email_{nom}.png'))
        page.click("#eq-nom-retenu button:has-text(\"C'est bon\")")
        page.wait_for_function("!document.getElementById('eq-nom-retenu')", timeout=5000)
        if page.evaluate("_eqLeads.find(x => x.id === 'c4').nom_famille") != 'Lafagne': erreurs.append(f'{nom} : nom pas écrit sur la fiche')
        if not any(m == 'PATCH' and 'nom_confirme' in (d or '') for m, u, d in appels): erreurs.append(f'{nom} : nom non confirmé')
        page.evaluate("eqFicheFermer()")

        # 6. Dénoncé sous un autre nom : bandeau rouge, « C'est corrigé »
        page.evaluate("eqOuvrirFiche('c5')")
        page.wait_for_selector('#eq-nom-ecart', timeout=5000)
        txt = page.inner_text('#eq-nom-ecart')
        for attendu in ('Dénoncé sous un autre nom', 'Morgane Lafagne', 'CARE PROMOTION, BOUYGUES'):
            if attendu not in txt: erreurs.append(f'{nom} : bandeau écart sans « {attendu} » : {txt!r}')
        page.click("#eq-nom-ecart button")
        page.wait_for_function("!document.getElementById('eq-nom-ecart')", timeout=5000)
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Dénonciations : tout est bon (bureau et iPhone).')
sys.exit(1 if erreurs else 0)
