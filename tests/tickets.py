# Test des tickets vendeurs → gérants (demande d'Alex du 11/11/2026) : texte remis au propre,
# saisie écrite et dictée (reconnaissance vocale simulée), envoi, page gérant (ordre, réponse),
# pastilles et réponse lue côté vendeur. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/tickets.py [dossier des captures]
import datetime, json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

def il_y_a(h):
    return (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=h)).isoformat()
LEADS = [{'id': 'c1', 'nom': 'Claire Martin', 'prenom': 'Claire', 'nom_famille': 'Martin', 'statut': 'Retour documentation', 'vendeur': 'Louis', 'date_lead': '2026-10-01', 'appels': []},
         {'id': 'c2', 'nom': 'Paul Durand', 'prenom': 'Paul', 'nom_famille': 'Durand', 'statut': 'Suivi', 'vendeur': 'Louis', 'date_lead': '2026-10-02', 'appels': []}]
TICKETS = [
    {'id': 't1', 'cree_le': il_y_a(5), 'auteur': 'Nour', 'type': 'question', 'urgence': 'normal', 'titre': 'Comment poser un rappel', 'message': 'Comment poser un rappel ?', 'saisie': 'ecrit', 'contexte': {}, 'statut': 'en_cours', 'pris_par': 'Alex'},
    {'id': 't2', 'cree_le': il_y_a(1), 'auteur': 'Louis', 'type': 'probleme', 'urgence': 'bloquant', 'titre': 'La sélection ne part pas', 'message': 'La sélection ne part pas.', 'saisie': 'vocal',
     'contact_id': 'c1', 'contact_nom': 'Claire Martin', 'contexte': {'page': 'Mes leads', 'appareil': 'iPhone', 'statut_client': 'Retour documentation'}, 'statut': 'nouveau'},
    {'id': 't3', 'cree_le': il_y_a(30), 'auteur': 'Louis', 'type': 'demande', 'urgence': 'jour', 'titre': 'Accès Ogic', 'message': 'Accès Ogic.', 'saisie': 'ecrit', 'contexte': {}, 'statut': 'regle',
     'reponse': 'C’est fait.', 'repondu_par': 'Théophile', 'repondu_le': il_y_a(2), 'reponse_vue_le': None},
]
# Reconnaissance vocale simulée : deux morceaux de phrase, puis fin
FAUX_MICRO = """
window.webkitSpeechRecognition = class {
  start() { setTimeout(() => {
      this.onresult({ resultIndex: 0, results: [Object.assign([{ transcript: 'euh le planning virgule il affiche rien' }], { isFinal: true })] });
      this.onresult({ resultIndex: 1, results: [null, Object.assign([{ transcript: 'depuis ce matin' }], { isFinal: true })] });
    }, 30); }
  stop() { setTimeout(() => this.onend && this.onend(), 10); }
};
"""

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.add_init_script(FAUX_MICRO)
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        envois, maj, vues = [], [], []
        def repond(r):
            u, m = r.request.url, r.request.method
            if 'supabase.co' not in u: return r.continue_()
            if '/rest/v1/tickets' in u and m == 'POST': envois.append(json.loads(r.request.post_data)); return r.fulfill(status=201, body='')
            if '/rest/v1/tickets' in u and m == 'PATCH': maj.append((u.split('id=eq.')[1], json.loads(r.request.post_data))); return r.fulfill(status=204, body='')
            if '/rest/v1/tickets' in u:
                liste = [t for t in TICKETS if 'auteur=eq.' not in u or t['auteur'] == u.split('auteur=eq.')[1].split('&')[0]]
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(liste))
            if '/rpc/ticket_reponse_vue' in u: vues.append(json.loads(r.request.post_data)['p_id']); return r.fulfill(status=204, body='')
            return r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
            # Texte remis au propre
            t = page.evaluate("tkNettoyer(\"euh je n'arrive pas a envoyer la sélection virgule le bouton reste gris point d'interrogation à la ligne merci\")")
            if not t.startswith("Je n'arrive") or ', le bouton' not in t or '\nMerci.' not in t or '?' not in t:
                erreurs.append(f'nettoyage inattendu : {t!r}')
            titre = page.evaluate("tkTitre('Le planning ne s’affiche plus depuis ce matin sur mon téléphone quand je l’ouvre depuis l’écran d’accueil et que je change de semaine. Merci.')")
            if len(titre) > 92 or not titre.endswith('…'): erreurs.append(f'titre trop long : {titre!r}')

        # ---- Vendeur : Louis écrit un ticket sur un client
        page.evaluate("ls => { _hideLogin(); MON_ROLE = { prenom: 'Louis', role: 'commercial' }; _eqLeads = ls; }", LEADS)
        page.evaluate("goTo('equipe-tickets', null)")
        page.wait_for_timeout(300)
        if 'C’est fait.' not in page.inner_text('#tk-mes-liste'): erreurs.append(f'{nom} : réponse du gérant absente de « Mes tickets »')
        if vues != ['t3']: erreurs.append(f'{nom} : réponse non marquée lue ({vues})')
        if page.is_visible('#nav-mestickets-pastille'): erreurs.append(f'{nom} : pastille « Mes tickets » encore allumée')

        page.evaluate("tkOuvrir('c1')")
        page.click('#tk-envoyer')  # sans type : refusé
        page.wait_for_timeout(200)
        if envois: erreurs.append(f'{nom} : ticket envoyé sans type')
        page.click('button.tk-type[data-v="probleme"]')
        page.click('#tk-dicter')
        page.wait_for_timeout(300)
        page.click('#tk-dicter')
        page.wait_for_timeout(200)
        val = page.input_value('#tk-message')
        if 'planning' not in val or 'depuis ce matin' not in val: erreurs.append(f'{nom} : dictée non reçue : {val!r}')
        page.click('button.tk-urgence[data-v="bloquant"]')
        apercu = page.inner_text('#tk-apercu')
        if 'Le planning, il affiche rien depuis ce matin' not in apercu or 'Claire Martin' not in apercu or 'Bloquant' not in apercu:
            erreurs.append(f'{nom} : aperçu inattendu : {apercu!r}')
        page.screenshot(path=str(SORTIE / f'tickets_saisie_{nom}.png'))
        page.click('#tk-envoyer')
        page.wait_for_timeout(300)
        if len(envois) != 1: erreurs.append(f'{nom} : {len(envois)} envoi(s)')
        else:
            e = envois[0]
            attendu = {'type': 'probleme', 'urgence': 'bloquant', 'saisie': 'vocal', 'contact_id': 'c1', 'contact_nom': 'Claire Martin',
                       'titre': 'Le planning, il affiche rien depuis ce matin', 'message': 'Le planning, il affiche rien depuis ce matin.'}
            for k, v in attendu.items():
                if e.get(k) != v: erreurs.append(f'{nom} : {k} = {e.get(k)!r} au lieu de {v!r}')
            if 'auteur' in e: erreurs.append(f'{nom} : la page envoie l’auteur')
            if e.get('contexte', {}).get('statut_client') != 'Retour documentation': erreurs.append(f'{nom} : contexte {e.get("contexte")}')
        if page.is_visible('#modal-ticket'): erreurs.append(f'{nom} : fenêtre restée ouverte')

        # ---- Gérant
        page.evaluate("() => { MON_ROLE = { prenom: 'Alex', role: 'gerant' }; }")
        page.evaluate("tkRafraichir()")
        page.wait_for_timeout(300)
        if page.inner_text('#nav-tickets-pastille') != '1': erreurs.append(f'{nom} : pastille gérant {page.inner_text("#nav-tickets-pastille")!r} au lieu de 1')
        page.evaluate("goTo('gerant-tickets', null)")
        page.wait_for_timeout(300)
        ordre = page.eval_on_selector_all('#tk-gerant-liste .tk-carte', 'els => els.map(e => e.dataset.id)')
        if ordre != ['t2', 't1']: erreurs.append(f'{nom} : ordre {ordre} au lieu de [t2, t1] (bloquant d’abord, réglés à part)')
        page.screenshot(path=str(SORTIE / f'tickets_gerant_{nom}.png'), full_page=False)
        page.click('.tk-carte[data-id="t2"] >> text=Répondre et régler')
        page.fill('#tk-rep-txt-t2', 'je regarde ça virgule renvoie la sélection dans 5 minutes')
        page.click('.tk-carte[data-id="t2"] >> text=Envoyer et régler')
        page.wait_for_timeout(300)
        if maj != [('t2', {'statut': 'regle', 'reponse': 'Je regarde ça, renvoie la sélection dans 5 minutes.'})]:
            erreurs.append(f'{nom} : mise à jour {maj}')
        page.click('#tk-filtres >> text=Réglés')
        if page.eval_on_selector_all('#tk-gerant-liste .tk-carte', 'els => els.map(e => e.dataset.id)') != ['t3']: erreurs.append(f'{nom} : filtre Réglés')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
