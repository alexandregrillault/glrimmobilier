# Test de la relance jusqu'au 3e essai : un lead en « Sans réponse » reste dans les activités
# tant qu'il n'a pas été essayé sur trois jours différents, sans rien écrire sur la fiche.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/relance_appel.py [dossier des captures]
import datetime, json, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

AUJ = datetime.date.today()
def il_y_a(n, h=10):
    return (datetime.datetime.combine(AUJ, datetime.time(h)) - datetime.timedelta(days=n)).isoformat() + '+01:00'
def lead(i, nom, jours, **k):
    l = {'id': i, 'nom': nom, 'prenom': '', 'statut': 'Sans réponse', 'vendeur': 'Louis', 'date_lead': '2026-10-01',
         'recu_le': il_y_a(max(jours + [1])), 'statut_maj': il_y_a(min(jours + [1])), 'appels': [{'le': il_y_a(j), 'vendeur': 'Louis'} for j in jours]}
    l.update(k)
    return l
LEADS = [
    lead('a', 'Sans Appel', []),                                 # 1er essai, aujourd'hui
    lead('b', 'Un Essai Ancien', [5]),                           # 2e essai, en retard
    lead('c', 'Deux Essais', [7, 5]),                            # 3e essai, en retard
    lead('d', 'Meme Jour', [5, 5]),                              # deux appels le même jour = un seul essai
    lead('e', 'Trois Faits', [6, 4, 3]),                         # terminé : sort de la liste
    lead('f', 'Trop Ancien', [20]),                              # paternité passée : pas de relance
    lead('g', 'Avec Rappel', [5], rappel_le=AUJ.isoformat()),    # le rappel posé l'emporte
    lead('h', 'Masque Avant', [5], activite_masquee_le=il_y_a(2)),  # déjà retiré autrefois : revient quand même
    lead('i', 'Client Joint', [5], statut='Sélections'),         # joint : plus de relance
    lead('j', 'Appele Aujourdhui', [0]),                         # essayé ce matin : reste affiché, prochain essai un autre jour
    lead('k', 'Deux Fois Ce Jour', [0]),                         # rappelé le jour même : même jour d'essai
    lead('l', 'Troisieme Ce Jour', [7, 5, 0]),                   # 3e essai fait aujourd'hui : reste jusqu'au soir
    lead('m', 'Rappel Deja Appele', [0], rappel_le=AUJ.isoformat()),  # un rappel du jour le dit aussi
]
LEADS[-3]['appels'].append({'le': il_y_a(0, 15), 'vendeur': 'Louis'})
LEADS[-2]['appels'][-1]['vendeur'] = 'Jules'
ATTENDU_ESSAI = {'a': 0, 'b': 1, 'c': 2, 'd': 1, 'h': 1, 'j': 1, 'k': 1, 'l': 3}

erreurs = []
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        ecritures = []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if r.request.method != 'GET' and '/contacts' in r.request.url: ecritures.append(r.request.post_data)
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            print('\n'.join(res))
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("ls => { _hideLogin(); _eqLeads = ls; _eqSelectionsAll = []; _eqSelections = {}; }", LEADS)

        # Qui doit relancer, et à quel essai
        r = page.evaluate("() => Object.fromEntries(_eqLeads.map(l => [l.id, (eqEssaiAFaire(l) || {n: null}).n]))")
        for i, l in r.items():
            if l != ATTENDU_ESSAI.get(i): erreurs.append(f'{nom} : {i} : essai {l}, attendu {ATTENDU_ESSAI.get(i)}')

        # Le prochain essai tombe un jour ouvré, jamais le jour même d'un essai
        j = page.evaluate("() => eqEssaiAFaire(_eqLeads.find(l => l.id === 'j'))")
        d = datetime.date.fromisoformat(j['le'])
        if d <= AUJ or d.weekday() > 4: erreurs.append(f'{nom} : prochain essai mal placé : {j}')

        # La page Activité, retards dépliés
        page.evaluate("_eqActVoirRetard = true; renderEqNotifs()")
        t = page.evaluate("() => document.getElementById('eq-notif-liste').innerText")
        for attendu in ('Rappeler Sans Appel', '1er essai sur 3', 'Rappeler Un Essai Ancien', '2e essai sur 3', '3e essai sur 3', 'Rappeler Masque Avant', 'Pas de réponse'):
            if attendu not in t: erreurs.append(f'{nom} : absent des activités : {attendu}')
        for attendu in ("Déjà appelé aujourd'hui à 10h00 · 1 essai sur 3 · prochain essai", "Déjà appelé aujourd'hui à 10h00 et 15h00", "Déjà appelé aujourd'hui à 10h00 par Jules · 3 essais faits sur 3"):
            if attendu not in t: erreurs.append(f'{nom} : absent des activités : {attendu}')
        n = t.count("Déjà appelé aujourd'hui")
        if n != 4: erreurs.append(f'{nom} : {n} mentions au lieu de 4')
        if t.count('Rappeler Rappel Deja Appele') != 1: erreurs.append(f'{nom} : rappel du jour')
        # Un lead déjà appelé peut être rappelé, passe après les autres et ne fait pas sonner la pastille
        if t.index('Rappeler Sans Appel') > t.index('Rappeler Appele Aujourdhui'): erreurs.append(f'{nom} : les leads déjà appelés doivent passer après')
        ligne = page.evaluate("() => [...document.querySelectorAll('#eq-notif-liste button')].filter(b => b.textContent.trim() === 'Pas de réponse').map(b => b.className)")
        if not any('btn-secondary' in c for c in ligne): erreurs.append(f'{nom} : pas de bouton pour rappeler un lead déjà appelé')
        if page.evaluate("() => +document.getElementById('eq-notif-badge').textContent") != 7: erreurs.append(f'{nom} : pastille : ' + page.evaluate("() => document.getElementById('eq-notif-badge').textContent"))
        for absent in ('Trois Faits', 'Trop Ancien', 'Client Joint'):
            if absent in t: erreurs.append(f'{nom} : ne devrait pas être affiché : {absent}')
        if t.count('Rappeler Avec Rappel') != 1: erreurs.append(f'{nom} : le rappel posé doit apparaître une fois')

        # Les retards se comptent et se cochent
        if not {'b', 'c', 'd', 'h'} <= set(page.evaluate("_eqActRetardIds()")): erreurs.append(f'{nom} : retards incomplets')

        # Aucune action de retrait sur une relance
        page.evaluate("eqActMenu('b', null)")
        m = page.evaluate("() => document.getElementById('eq-act-menu').innerText")
        if 'Retirer' in m or 'Passer en Sans réponse' in m or 'Reporter' not in m: erreurs.append(f'{nom} : menu relance : {m}')
        page.evaluate("eqActMenuFermer(); eqActMenu('g', null)")
        if 'Retirer' not in page.evaluate("() => document.getElementById('eq-act-menu').innerText"): erreurs.append(f'{nom} : le menu normal a perdu Retirer')
        page.evaluate("eqActMenuFermer(); eqActAction('retirer', 'b'); eqActAction('sansreponse', 'b')")
        if page.evaluate("!!document.getElementById('eq-act-modal') || [...document.body.children].some(x => /Retirer de la liste/.test(x.innerText || '') && x.id !== 'bloc-test' && getComputedStyle(x).position === 'fixed')"):
            erreurs.append(f'{nom} : une fenêtre de retrait s\'est ouverte sur une relance')

        # Afficher la liste n'écrit rien sur les fiches : la paternité ne bouge pas
        if ecritures: erreurs.append(f'{nom} : écriture inattendue : {ecritures}')

        # « Pas de réponse » note l'essai du jour
        page.evaluate("eqAppelSansReponse('b')")
        page.wait_for_timeout(200)
        if not any('Sans réponse' in (e or '') for e in ecritures): erreurs.append(f'{nom} : l\'essai n\'a pas été envoyé : {ecritures}')

        page.evaluate("_eqActVoirRetard = true; renderEqNotifs()")
        page.evaluate("""() => { const b = document.createElement('div'); b.id = 'bloc-test';
            b.style.cssText = 'position:fixed;inset:0;z-index:9999;background:#fff;padding:16px;overflow:auto';
            b.innerHTML = document.getElementById('eq-notif-liste').innerHTML; document.body.appendChild(b); }""")
        if nom == 'iphone' and page.evaluate("(() => { const b = document.getElementById('bloc-test'); return b.scrollWidth > b.clientWidth + 1; })()"):
            erreurs.append('iphone : la liste déborde en largeur')
        page.screenshot(path=str(SORTIE / f'relance_appel_{nom}.png'))
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon')
sys.exit(1 if erreurs else 0)
