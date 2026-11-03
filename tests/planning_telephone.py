# Test du planning sur le téléphone : la fenêtre « Sur mon téléphone » de Mon planning (bureau et iPhone),
# puis le calendrier produit par l'edge function planning-ics, exécutée par Node avec une base simulée.
# Lancer : ~/glr-pige-robot/.venv/bin/python tests/planning_telephone.py [dossier des captures]
import json, pathlib, shutil, subprocess, sys, tempfile
from playwright.sync_api import sync_playwright

ICI = pathlib.Path(__file__).resolve().parent
INDEX = ICI.parent / 'index.html'
FONCTION = ICI.parent / 'supabase' / 'functions' / 'planning-ics' / 'index.ts'
SORTIE = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICI
CLE1, CLE2 = 'a' * 48, 'b' * 48

erreurs = []

# ---- 1. La fenêtre dans le CRM ----
with sync_playwright() as p:
    nav = p.chromium.launch()
    for nom, vp in (('bureau', {'width': 1400, 'height': 1000}), ('iphone', {'width': 390, 'height': 844})):
        page = nav.new_page(viewport=vp, timezone_id='Europe/Paris', locale='fr-FR')
        page.on('pageerror', lambda e: erreurs.append(f'{nom} : {e}'))
        appels = []
        def repond(r):
            if 'supabase.co' not in r.request.url: return r.continue_()
            if 'rpc/planning_abonnement_cle' in r.request.url:
                corps = json.loads(r.request.post_data)
                appels.append(corps)
                return r.fulfill(status=200, content_type='application/json', body=json.dumps(CLE2 if corps.get('renouveler') else CLE1))
            r.fulfill(status=200, content_type='application/json', body='[]')
        page.route('**/*', repond)
        page.goto(INDEX.as_uri())
        if nom == 'bureau':
            res = page.evaluate("""() => [...document.querySelectorAll('script:not([src])')].map((s, i) => {
                try { new Function(s.textContent); return 'bloc ' + i + ' : ok'; } catch (e) { return 'bloc ' + i + ' : ' + e.message; } })""")
            erreurs += [x for x in res if not x.endswith(': ok')]
        page.evaluate("""() => { _hideLogin(); document.querySelectorAll('.page').forEach(x => x.classList.remove('active'));
            document.getElementById('page-equipe-planning').classList.add('active'); }""")
        page.get_by_role('button', name='Sur mon téléphone').click()
        page.wait_for_selector('#plan-abo-url')
        if appels != [{'renouveler': False}]: erreurs.append(f'{nom} : appel de la clé : {appels}')
        liens = page.evaluate("[...document.querySelectorAll('#plan-abo-corps a')].map(a => a.getAttribute('href'))")
        attendu = 'webcal://hydqfbxdtpmbuooexekp.supabase.co/functions/v1/planning-ics?cle=' + CLE1
        if not liens or liens[0] != attendu: erreurs.append(f'{nom} : lien iPhone : {liens}')
        if len(liens) < 2 or 'calendar.google.com' not in liens[1] or CLE1 not in liens[1]: erreurs.append(f'{nom} : lien Google : {liens}')
        if page.input_value('#plan-abo-url') != attendu.replace('webcal:', 'https:'): erreurs.append(f'{nom} : adresse à copier')
        if page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1"): erreurs.append(f'{nom} : la page déborde')
        page.screenshot(path=str(SORTIE / f'planning_telephone_{nom}.png'))

        # Changer le lien : confirmation, nouvelle clé
        page.once('dialog', lambda d: d.accept())
        page.get_by_role('button', name='Changer le lien').click()
        page.wait_for_function(f"document.getElementById('plan-abo-url') && document.getElementById('plan-abo-url').value.endsWith('{CLE2}')")
        if appels[-1] != {'renouveler': True}: erreurs.append(f'{nom} : renouvellement : {appels}')
        page.get_by_role('button', name='Fermer', exact=True).click()
        if page.query_selector('#plan-abo-modal'): erreurs.append(f'{nom} : la fenêtre ne se ferme pas')
    nav.close()

# ---- 2. Le calendrier servi au téléphone ----
CRENEAUX = [
    {'id': '11111111-1111-1111-1111-111111111111', 'debut': '2026-11-05T09:00:00Z', 'fin': '2026-11-05T09:30:00Z', 'mode': 'visio',
     'lieu': 'https://meet.google.com/abc-defg-hij', 'statut': 'confirme', 'contact_id': 'c1', 'client_nom': 'Hélène Dupont-Lefèvre',
     'client_message': 'Un T3 à Montreuil, budget 350, avec balcon; idéalement proche du métro', 'origine': None, 'titre': None, 'categorie': None, 'bloquant': True},
    {'id': '22222222-2222-2222-2222-222222222222', 'debut': '2026-11-05T10:00:00Z', 'fin': '2026-11-05T10:10:00Z', 'mode': 'telephone',
     'lieu': None, 'statut': 'reserve', 'contact_id': 'c2', 'client_nom': 'Karim B.', 'client_message': None, 'origine': None, 'titre': None, 'categorie': None, 'bloquant': True},
    {'id': '33333333-3333-3333-3333-333333333333', 'debut': '2026-11-06T13:00:00Z', 'fin': '2026-11-06T15:30:00Z', 'mode': 'agence',
     'lieu': None, 'statut': 'confirme', 'contact_id': None, 'client_nom': None, 'client_message': None, 'origine': 'perso', 'titre': None, 'categorie': 'formation', 'bloquant': False},
    {'id': '44444444-4444-4444-4444-444444444444', 'debut': '2026-11-07T08:00:00Z', 'fin': '2026-11-07T08:30:00Z', 'mode': 'telephone',
     'lieu': None, 'statut': 'confirme', 'contact_id': 'c3', 'client_nom': 'Paul Martin', 'client_message': None, 'origine': 'rappel', 'titre': None, 'categorie': None, 'bloquant': True},
    {'id': '55555555-5555-5555-5555-555555555555', 'debut': '2026-11-08T08:00:00Z', 'fin': '2026-11-08T08:10:00Z', 'mode': 'telephone',
     'lieu': None, 'statut': 'propose', 'contact_id': 'c4', 'client_nom': 'Zoé', 'client_message': None, 'origine': None, 'titre': None, 'categorie': None, 'bloquant': True},
]
HARNAIS = """
const CRENEAUX = %s;
const filtres = [];
globalThis.Deno = { env: { get: (k) => 'x' }, serve: (h) => { globalThis.HANDLER = h; } };
function createClient() {
  return { from(table) {
    const f = { table, eq: [], neq: [] };
    const q = {
      select() { return q; }, eq(c, v) { f.eq.push([c, v]); return q; }, neq(c, v) { f.neq.push([c, v]); return q; },
      gte() { return q; }, lte() { return q; }, order() { return q; }, limit() { filtres.push(f); return Promise.resolve({ data: CRENEAUX, error: null }); },
      maybeSingle() { filtres.push(f); const cle = (f.eq.find(x => x[0] === 'cle') || [])[1];
        return Promise.resolve({ data: cle === '%s' ? { vendeur: 'Anais' } : null }); }
    };
    return q;
  } };
}
"""
FIN = """
const base = 'https://x.supabase.co/functions/v1/planning-ics?cle=';
const sortie = {};
for (const [k, url] of [['bon', base + '%s'], ['inconnu', base + '%s'], ['vide', base]]) {
  const r = await HANDLER(new Request(url));
  sortie[k] = { status: r.status, type: r.headers.get('content-type'), corps: await r.text() };
}
sortie.filtres = filtres;
console.log(JSON.stringify(sortie));
"""
node = shutil.which('node')
if not node:
    erreurs.append('calendrier : Node introuvable, test non fait')
else:
    src = FONCTION.read_text(encoding='utf-8')
    if '\\u' in ''.join(l for l in src.splitlines() if not l.strip().startswith('//')).replace('\\\\', ''):
        erreurs.append('calendrier : séquence \\u dans la fonction')
    src = src.replace('import { createClient } from "npm:@supabase/supabase-js@2";', HARNAIS % (json.dumps(CRENEAUX), CLE1)) + FIN % (CLE1, CLE2)
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / 'planning.mts'
        f.write_text(src, encoding='utf-8')
        r = subprocess.run([node, str(f)], capture_output=True, text=True)
    if r.returncode:
        erreurs.append('calendrier : ' + r.stderr[-800:])
    else:
        s = json.loads(r.stdout)
        if s['inconnu']['status'] != 404 or s['vide']['status'] != 404: erreurs.append('calendrier : une mauvaise clé est acceptée')
        bon = s['bon']
        if bon['status'] != 200 or not bon['type'].startswith('text/calendar'): erreurs.append(f"calendrier : réponse {bon['status']} {bon['type']}")
        ics = bon['corps']
        (SORTIE / 'planning_telephone.ics').write_text(ics, encoding='utf-8')
        cren = [x for x in s['filtres'] if x['table'] == 'creneaux']
        if not cren or ['vendeur', 'Anais'] not in cren[0]['eq'] or ['statut', 'libre'] not in cren[0]['neq']: erreurs.append(f'calendrier : filtres {cren}')
        if '\r\n' not in ics or any(len(l.encode('utf-8')) > 75 for l in ics.split('\r\n')): erreurs.append('calendrier : lignes trop longues ou mal coupées')
        deplie = ics.replace('\r\n ', '')
        for a in ('X-WR-CALNAME:GLR — Anais', 'SUMMARY:Visio — Hélène Dupont-Lefèvre', 'DTSTART:20261105T090000Z', 'DTEND:20261105T093000Z',
                  'LOCATION:https://meet.google.com/abc-defg-hij', 'avec balcon\\; idéalement', 'budget 350\\,',
                  'SUMMARY:À valider · Appel — Karim B.', 'SUMMARY:Formation', 'TRANSP:TRANSPARENT', 'SUMMARY:Rappeler Paul Martin',
                  'SUMMARY:Proposé · Appel — Zoé', 'index.html?fiche=c1', 'END:VCALENDAR'):
            if a not in deplie: erreurs.append(f'calendrier : absent : {a}')
        if deplie.count('BEGIN:VEVENT') != 5: erreurs.append('calendrier : nombre de rendez-vous')
        if deplie.count('BEGIN:VALARM') != 2: erreurs.append(f"calendrier : alertes {deplie.count('BEGIN:VALARM')} (attendu : visio et rappel confirmés)")
        if deplie.count('STATUS:TENTATIVE') != 2: erreurs.append('calendrier : statuts provisoires')

print('\n'.join(erreurs) if erreurs else 'tout est bon')
sys.exit(1 if erreurs else 0)
