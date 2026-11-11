# Parcours « budget fait par le client » (11/11/2026) : simulateur -> feuille sélection
# (écart de loyer, aides en euros), encadré budget de la page rendez-vous, budget déjà fait.
import json, re
from playwright.sync_api import sync_playwright
G='file:///Users/alexandregrillaultlaroche/Documents/GLR/'
import os
OUT=os.path.dirname(os.path.abspath(__file__))+'/budget_client_'
TAUX={"t15":3.81,"t20":3.9,"t25":4.05,"date_site":"09/11/2026"}
BIENS=[
 {"titre":"T3 Bagneux — Les Jardins","prix":"289 000 €","surface":"64","commune":"Bagneux","codePostal":"92220","lien":"lot-bagneux","typologie":"T3"},
 {"titre":"T2 Saint-Denis — Pleyel","prix":"249 000 €","surface":"44","commune":"Saint-Denis","codePostal":"93200","lien":"lot-sd","typologie":"T2"},
]
erreurs=[]
def surveiller(p, nom):
    p.on('pageerror', lambda e: erreurs.append(nom+': '+str(e)))

with sync_playwright() as pw:
    b=pw.chromium.launch()

    # ---------- 1. Simulateur : le vendeur confirme le budget avec les lots ----------
    posted=[]
    def route_simu(r):
        u=r.request.url
        if 'taux-marche' in u: return r.fulfill(json=TAUX)
        if '/functions/v1/selection/' in u:
            if r.request.method=='POST': posted.append(json.loads(r.request.post_data)); return r.fulfill(json={"ok":True})
            return r.fulfill(json={"ok":True,"biens":BIENS})
        if 'supabase.co' in u: return r.fulfill(json=[])
        return r.continue_()
    p=b.new_page(viewport={'width':1280,'height':900}); surveiller(p,'simulateur')
    p.route('**/*', route_simu)
    p.goto(G+'glrimmobilier/simulateur.html?t=abc123abc')
    p.wait_for_timeout(1500)
    vide=p.eval_on_selector('#loyerActuel','e=>e.value')
    p.evaluate("""()=>{const s=(i,v)=>{const e=document.getElementById(i); e.value=v; e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true}));};
      s('projet','rp'); s('logement','loc'); s('loyerActuel','1100'); s('apport','20000'); s('foyer','3');
      S.nb=2; S.emp[0]=Object.assign({},S.emp[0],{rev:2800,age:34}); S.emp[1]=Object.assign({},S.emp[1]||{},{rev:2100,age:32});
      renderEmprunteurs(); recalc(); }""")
    p.wait_for_timeout(500)
    p.click('#btnEnregistrerSim'); p.wait_for_timeout(800)
    assert posted, 'aucun envoi du simulateur'
    pl=posted[-1]
    print('loyer vide par défaut :', repr(vide))
    print('loyerActuel envoyé :', pl.get('loyerActuel'))
    for l in pl['lots']: print('lot', l['cle'], l['mensualite'], '€/mois, gains', l.get('gains'))
    p.close()

    # ---------- 2. Feuille sélection avec cette simulation ----------
    SIM={"date":"2026-11-11T10:00:00Z","budgetMax":pl.get('budgetMax'),"montage":pl.get('montage'),"objectif":None,
         "loyerActuel":pl.get('loyerActuel'),"lots":[{k:l.get(k) for k in ('cle','mensualite','economie','gains','eligible')} for l in pl['lots']]}
    SEL={"ok":True,"expired":False,"prenom":"Camille","vendeur":"Nour","message":"","biens":BIENS,"simulation":SIM}
    def route_sel(r):
        u=r.request.url
        if '/functions/v1/selection/' in u:
            if r.request.method=='POST': return r.fulfill(json={"ok":True})
            return r.fulfill(json=SEL)
        if 'supabase.co' in u: return r.fulfill(json=[])
        return r.continue_()
    for nom,larg in (('iphone',390),('bureau',1280)):
        p=b.new_page(viewport={'width':larg,'height':900}); surveiller(p,'selection '+nom)
        p.route('**/*', route_sel)
        p.goto(G+'glr-site/selection/index.html?t=abc123abc'); p.wait_for_timeout(1500)
        n=p.locator('.simu-lot').count()
        txt=p.locator('.simu-lot').all_inner_texts()
        if nom=='iphone':
            print('blocs mensualité :', n)
            for t in txt: print('---\n'+t)
            print('défilement horizontal :', p.evaluate('document.documentElement.scrollWidth>innerWidth'))
        el=p.locator('.simu-lot').first
        el.scroll_into_view_if_needed()
        p.screenshot(path=OUT+f'selection_lot_{nom}.png', clip=None, full_page=False)
        p.evaluate("()=>document.querySelectorAll('*').forEach(e=>{const c=getComputedStyle(e).position; if(c==='fixed'||c==='sticky') e.style.display='none';})")
        el.screenshot(path=OUT+f'selection_lot_zoom_{nom}.png')
        p.close()

    # ---------- 3. Page rendez-vous : encadré budget ----------
    def rdv_data(budgetFait, reserve=True):
        d={"ok":True,"expired":False,"public":False,"prenom":"Camille","vendeur":"Nour","bien":{"ville":"Bagneux (92220)","typologie":"Appartement 3 pièces","prix":289000},
           "formats":{"visio":{"duree":30,"mode":"visio"},"appel":{"duree":10,"mode":"telephone"}},"creneaux":[],"propositions":[],"visio":""}
        if budgetFait is not None: d["budgetFait"]=budgetFait
        d["rdv"]={"demande":True,"reserve":True,"confirme":False,"refuse":False,"debut":"2026-11-14T09:00:00Z","fin":"2026-11-14T09:30:00Z","mode":"visio","format":"visio"} if reserve else {}
        return d
    cas=[('rdv_sans_budget',rdv_data(False),True),('rdv_budget_fait',rdv_data(True),False),('rdv_ancien_serveur',rdv_data(None),False),('rdv_pas_encore_pris',rdv_data(False,False),False)]
    for nom,data,attendu in cas:
        for vue,larg in (('iphone',390),('bureau',1280)):
            p=b.new_page(viewport={'width':larg,'height':900}); surveiller(p,nom)
            def fab(data):
                return lambda r: r.fulfill(json=data) if '/functions/v1/rdv/' in r.request.url else (r.fulfill(json=[]) if 'supabase.co' in r.request.url else r.continue_())
            p.route('**/*', fab(data))
            p.goto(G+'glr-site/rdv/index.html?t=abc123abc'); p.wait_for_timeout(1000)
            vu=p.locator('.budget-invite').count()>0
            if vue=='iphone':
                href=p.get_attribute('.budget-btn','href') if vu else None
                print(nom, 'encadré affiché :', vu, '(attendu', attendu, ')', href or '')
                assert vu==attendu, nom
            if nom=='rdv_sans_budget': p.screenshot(path=OUT+f'{nom}_{vue}.png', full_page=True)
            p.close()

    # ---------- 4. Page budget : déjà fait / fin de parcours ----------
    p=b.new_page(viewport={'width':390,'height':844}); surveiller(p,'budget deja')
    p.route('**/*', lambda r: r.fulfill(json=TAUX) if 'taux-marche' in r.request.url else (r.fulfill(json={"ok":True,"prenom":"Camille","vendeur":"Nour","bien":{},"budgetFait":True}) if '/functions/v1/rdv/' in r.request.url else r.continue_()))
    p.goto(G+'glr-site/budget/index.html?t=abc123abc'); p.wait_for_timeout(800)
    print('budget déjà fait :', p.inner_text('#contenu').replace('\n',' | '))
    p.screenshot(path=OUT+'budget_deja_fait_iphone.png', full_page=True); p.close()

    b.close()
print('erreurs JS :', erreurs or 'aucune')
