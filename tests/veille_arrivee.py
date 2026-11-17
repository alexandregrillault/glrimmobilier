# Clients « En veille » chez un collègue et arrivée chez un nouveau vendeur (demande d'Alex du 17/11/2026) :
# (a) en veille chez Théophile, Alexandre dans recu_par AVANT la mise en veille → invisible chez Alexandre,
#     absent de ses Premiers appels ;
# (b) Alexandre dans recu_par APRÈS la mise en veille → visible chez lui et dans ses Premiers appels
#     avec « En veille chez Théophile depuis le …, revenu vers toi » ;
# (c) le même client vu par Théophile → inchangé (visible, pas de Premier appel) ;
# (d) après un appel noté par Alexandre, la ligne Premier appel disparaît chez lui.
# En plus : une fiche réattribuée à Alexandre (suivie avant par Louis) arrive dans ses Premiers appels ;
# compteurs de « Mes leads » cohérents. Bureau et iPhone.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/veille_arrivee.py [dossier des captures]
import datetime, pathlib, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI

MAINT = datetime.datetime.now(datetime.timezone.utc)
def il_y_a(j): return (MAINT - datetime.timedelta(days=j)).isoformat()
VEILLE = il_y_a(3)
def veille(i, nom, recu_alex):
    return {'id': i, 'nom': nom, 'prenom': '', 'statut': 'En veille', 'vendeur': 'Théophile', 'date_lead': '2026-10-01',
            'statut_maj': VEILLE, 'veille_depuis': VEILLE, 'vendeur_depuis': il_y_a(20), 'premiere_action_le': il_y_a(19),
            'recu_par': [{'vendeur': 'Alexandre', 'le': recu_alex}, {'vendeur': 'Théophile', 'le': il_y_a(20)}],
            'vendeur_historique': [], 'appels': [], 'activites': []}
AVANT = veille('a1', 'Avant Veille', il_y_a(25))      # (a) reçu par Alexandre avant la veille
APRES = veille('b1', 'Apres Veille', il_y_a(1))       # (b) refait une demande chez Alexandre après
APRES['recu_par'] = [{'vendeur': 'Théophile', 'le': il_y_a(20)}, {'vendeur': 'Alexandre', 'le': il_y_a(1)}]
REATTRIB = {'id': 'r1', 'nom': 'Reattribue Client', 'prenom': '', 'statut': 'Suivi', 'vendeur': 'Alexandre', 'date_lead': '2026-10-01',
            'statut_maj': il_y_a(9), 'vendeur_depuis': il_y_a(2), 'premiere_action_le': il_y_a(9), 'recu_par': [{'vendeur': 'Louis', 'le': il_y_a(10)}],
            'vendeur_historique': [{'vendeur': 'Louis', 'du': il_y_a(10), 'au': il_y_a(2), 'motif': 'réattribué par un gérant'}],
            'appels': [], 'activites': []}
SANS_VEILLE_DATE = veille('z1', 'Sans Date', il_y_a(1))
SANS_VEILLE_DATE['veille_depuis'] = None
SANS_VEILLE_DATE['statut_maj'] = il_y_a(2)        # statut_maj sert de date de mise en veille → reçu après : visible
TOUS = [AVANT, APRES, REATTRIB, SANS_VEILLE_DATE]

PREP = """([tous, prenom]) => {
  _hideLogin(); MON_ROLE = { prenom, role: 'gerant' }; data.vendeurs = [];
  const s = document.getElementById('eq-leads-vendeur'); if (s) s.value = '';
  if (typeof selectedVendeurId !== 'undefined') selectedVendeurId = null;
  _eqLeads = JSON.parse(JSON.stringify(tous)).filter(l => eqLeadVisiblePour(l, prenom));
  _eqLeads.forEach(l => l._conserve = false);
  _eqActVoirRetard = true;   // les arrivées de plus de 48 h sont dans le retard, déplié
  renderEqNotifs();
  return { ids: _eqLeads.map(l => l.id), activites: document.getElementById('eq-notif-liste').innerText };
}"""

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
            erreurs += [x for x in res if not x.endswith(': ok')]

        # ---- Alexandre
        r = page.evaluate(PREP, [TOUS, 'Alexandre'])
        if 'a1' in r['ids']: erreurs.append(f'{nom} (a) : client reçu avant la veille visible chez Alexandre')
        if 'Avant Veille' in r['activites']: erreurs.append(f'{nom} (a) : client reçu avant la veille dans les activités')
        if 'b1' not in r['ids']: erreurs.append(f'{nom} (b) : client reçu après la veille absent de Mes leads')
        if 'Premier appel — Apres Veille' not in r['activites'] or 'En veille chez Théophile depuis le' not in r['activites'] or 'revenu vers toi' not in r['activites']:
            erreurs.append(f'{nom} (b) : Premier appel absent ou texte inattendu : {r["activites"][:600]}')
        if 'z1' not in r['ids']: erreurs.append(f'{nom} : veille sans veille_depuis — statut_maj non pris en compte')
        if 'Premier appel — Reattribue Client' not in r['activites'] or 'Suivi avant par Louis' not in r['activites']:
            erreurs.append(f'{nom} : fiche réattribuée absente des Premiers appels')
        # Compteurs de Mes leads : la case En veille ne compte que les visibles
        page.evaluate("renderEquipeLeadsTable()")
        nVeille = page.evaluate("_eqLeads.filter(estEnVeille).length")
        if nVeille != 2: erreurs.append(f'{nom} : {nVeille} clients en veille comptés chez Alexandre au lieu de 2')
        page.evaluate("""() => { const b = document.createElement('div'); b.id = 'bloc-test';
            b.style.cssText = 'position:fixed;inset:0;z-index:9999;background:#fff;padding:16px;overflow:auto';
            b.innerHTML = document.getElementById('eq-notif-liste').innerHTML; document.body.appendChild(b); }""")
        page.screenshot(path=str(SORTIE / f'veille_arrivee_{nom}.png'))
        page.evaluate("document.getElementById('bloc-test').remove()")

        # (d) Alexandre note un appel : la ligne disparaît
        t = page.evaluate("""() => { const l = _eqLeads.find(x => x.id === 'b1');
            l.appels = [{ vendeur: 'Alexandre', le: new Date().toISOString() }];
            renderEqNotifs(); return document.getElementById('eq-notif-liste').innerText; }""")
        if 'Apres Veille' in t: erreurs.append(f'{nom} (d) : la ligne Premier appel reste après un appel noté')
        # Ligne retirée : même effet
        t = page.evaluate("""() => { const l = _eqLeads.find(x => x.id === 'r1');
            const c = _eqActCorps('retirer', l); Object.assign(l, c);
            renderEqNotifs(); return [JSON.stringify(c), document.getElementById('eq-notif-liste').innerText]; }""")
        if 'activite_masquee_le' not in t[0] or 'Reattribue Client' in t[1]: erreurs.append(f'{nom} : retrait de la ligne d’arrivée : {t[0]}')

        # ---- (c) Théophile : inchangé
        r = page.evaluate(PREP, [TOUS, 'Théophile'])
        if not {'a1', 'b1', 'z1'} <= set(r['ids']): erreurs.append(f'{nom} (c) : Théophile ne voit plus ses clients en veille : {r["ids"]}')
        if 'Premier appel — Apres Veille' in r['activites'] or 'revenu vers toi' in r['activites']:
            erreurs.append(f'{nom} (c) : Premier appel affiché chez le propriétaire')
        page.close()
    nav.close()

print('\n'.join(erreurs) if erreurs else 'Tout est bon.')
sys.exit(1 if erreurs else 0)
