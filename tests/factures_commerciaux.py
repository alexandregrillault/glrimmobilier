"""Factures de commission : paiement au choix du gérant dès la signature notaire.

Lancer : ~/glr-pige-robot/.venv/bin/python tests/factures_commerciaux.py
"""
import json, pathlib, re, sys
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
PAGE = (ICI.parent / 'index.html').as_uri()
SORTIE = ICI

VENTES = [
    # Chikaoui : signée, avance déjà payée, promoteur pas encore payé
    {'id': 'v1', 'client': 'Chikaoui', 'programme': 'Central Square', 'lot': 'A501', 'statut': 'facture', 'vendeurId': 'lou',
     'honoraires': 19225, 'taux': 75, 'avanceAccordee': True, 'avanceMontant': 3419, 'dateSignatureNotaire': '2026-07-23'},
    # Vente payée, rien facturé : prête
    {'id': 'v2', 'client': 'Frank', 'programme': 'Japy', 'statut': 'facture-payee', 'vendeurId': 'lou', 'honoraires': 10000, 'taux': 60},
    # Pas encore signée : absente
    {'id': 'v3', 'client': 'Futur', 'programme': 'Hameau', 'statut': 'reservation', 'vendeurId': 'lou', 'honoraires': 8000, 'taux': 50,
     'dateSignatureNotaire': '2099-01-01'},
]
FAC = [{'id': 'f1', 'numero': 'LOUIS-2026-002', 'vente_id': 'v1', 'vendeur_id': 'lou', 'type': 'avance', 'ht': 3419, 'ttc': 3419,
        'statut': 'payee', 'date_facture': '2026-10-13', 'vente': {'programme': 'Central Square'}}]

erreurs = []
with sync_playwright() as p:
    b = p.chromium.launch()
    for largeur, nom in [(1280, 'bureau'), (390, 'iphone')]:
        pg = b.new_page(viewport={'width': largeur, 'height': 900})
        appels = []
        def route(r):
            if 'facture_commerciale_emettre_libre' in r.request.url:
                corps = json.loads(r.request.post_data)
                appels.append(corps)
                rec = {'id': 'f2', 'numero': 'LOUIS-2026-003', 'vente_id': corps['p_vente'], 'vendeur_id': 'lou', 'type': 'solde',
                       'ht': corps['p_montant'], 'ttc': corps['p_montant'], 'statut': 'emise', 'date_facture': '2026-11-10',
                       'emetteur': {}, 'payeur': {}, 'vente': {'programme': 'Central Square', 'commissionTotale': 14418.75, 'dejaFacture': []}}
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(rec))
            r.fulfill(status=200, content_type='application/json', body='[]')
        pg.route(re.compile(r'.*supabase\.co.*'), route)
        pg.on('pageerror', lambda e: erreurs.append(str(e)))
        pg.goto(PAGE)
        pg.evaluate("""([ventes, fac]) => {
          _hideLogin();
          window.confirm = () => true; window.open = () => null; 
          data.ventes = ventes; _facCom = fac;
          data.vendeurs = [{id:'lou', prenom:'Louis', nom:'Test', role:'Commercial indépendant', facturation:{statut:'ei', siren:'1', adresse:'Paris', tva:false}}];
          goTo('factures', null);
          facTab('commerciaux');
        }""", [VENTES, FAC])
        lignes = pg.evaluate("[...document.querySelectorAll('#fac-panel-commerciaux table')[0].querySelectorAll('tbody tr')].map(t => t.innerText)")
        assert len(lignes) == 2, lignes
        assert 'Frank' in lignes[0], 'la vente payée passe en premier'
        assert 'Chikaoui' in lignes[1] and 'Promoteur pas encore payé' in lignes[1], lignes[1]
        assert pg.input_value('#fac-com-mt-v1') == '10999.75', pg.input_value('#fac-com-mt-v1')
        assert '(1 à émettre)' in pg.inner_text('#fac-tab-commerciaux')
        pg.fill('#fac-com-mt-v1', '20000')
        pg.click('#fac-panel-commerciaux tbody tr:nth-child(2) button')
        assert not appels, 'montant trop haut refusé'
        pg.fill('#fac-com-mt-v1', '5000')
        pg.click('#fac-panel-commerciaux tbody tr:nth-child(2) button')
        pg.wait_for_timeout(300)
        assert appels and appels[0]['p_montant'] == 5000 and appels[0]['p_vente'] == 'v1', appels
        pg.screenshot(path=str(SORTIE / f'factures_commerciaux_{nom}.png'), full_page=False)
        pg.close()
    b.close()

if erreurs:
    print('Erreurs JS :', erreurs[:3]); sys.exit(1)
print('Tout est bon.')
