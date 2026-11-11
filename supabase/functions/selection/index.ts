import { createClient } from 'npm:@supabase/supabase-js@2';

// Page publique de sélection hébergée sur GitHub Pages (glrimmobilier)
// Depuis le 02/09/2026 la page vit sur le site de la maison (dépôt glr-site,
// selection/index.html). Tant que ce dossier n'est pas en ligne, on retombe sur
// l'ancienne adresse GitHub Pages : aucun lien déjà envoyé ne doit casser.
const PAGE_URL = 'https://www.glrimmobilier.com/selection/';
const PAGE_URL_SECOURS = 'https://alexandregrillault.github.io/glrimmobilier/selection.html';
let _pageOk: { ok: boolean; a: number } | null = null;
async function pageUrl(): Promise<string> {
  if (_pageOk && Date.now() - _pageOk.a < 5 * 60 * 1000) return _pageOk.ok ? PAGE_URL : PAGE_URL_SECOURS;
  let ok = false;
  try {
    const r = await fetch(PAGE_URL, { method: 'HEAD', signal: AbortSignal.timeout(3000) });
    ok = r.ok;
  } catch (_) { ok = false; }
  _pageOk = { ok, a: Date.now() };
  return ok ? PAGE_URL : PAGE_URL_SECOURS;
}

// Fenêtre de proposition des créneaux de RDV au client
const RDV_JOURS_VISIBLES = 21;

// Deux formats de rendez-vous (choix d'Alex, 2 septembre 2026), les mêmes que
// sur le lien de rendez-vous envoyé par mail :
//   · visio : 30 min, on prend le temps de montrer ;
//   · appel : 10 min par téléphone, une première esquisse du projet.
// Le vendeur ouvre ses disponibilités par créneaux de 10 min ; le client ne
// bloque que la durée de son format via reserver_duree(), qui enchaîne les
// créneaux contigus et rend le reste de la plage proposable à d'autres.
const FORMATS: Record<string, { duree: number; mode: string }> = {
  visio: { duree: 30, mode: 'visio' },
  appel: { duree: 10, mode: 'telephone' }
};
const formatDe = (v: unknown): string | null => (typeof v === 'string' && FORMATS[v]) ? v : null;
const dureeMin = (c: any) => Math.round((new Date(c.fin).getTime() - new Date(c.debut).getTime()) / 60000);

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
};

const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// ---------- Mise en forme française ----------
const euros = (n: unknown) => {
  const v = Number(n);
  if (!Number.isFinite(v) || v <= 0) return '';
  return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(Math.round(v)) + ' €';
};
const m2 = (n: unknown) => {
  const v = Number(n);
  if (!Number.isFinite(v) || v <= 0) return '';
  return v.toFixed(2).replace('.', ',').replace(/,00$/, '') + ' m²';
};
const EXPOSITIONS: Record<string, string> = {
  N: 'Nord', S: 'Sud', E: 'Est', O: 'Ouest', W: 'Ouest',
  NE: 'Nord-Est', NO: 'Nord-Ouest', NW: 'Nord-Ouest',
  SE: 'Sud-Est', SO: 'Sud-Ouest', SW: 'Sud-Ouest', TRAVERSANT: 'Traversant'
};
const ANNEXES: Record<string, string> = {
  PARKING: 'Parking', BOX: 'Box', GARAGE: 'Garage', CELLAR: 'Cave', CAVE: 'Cave',
  TERRACE: 'Terrasse', BALCONY: 'Balcon', GARDEN: 'Jardin', LOGGIA: 'Loggia', ATTIC: 'Grenier'
};

// ---------- Adresse du programme ----------
// Otaree livre l'adresse complète du programme dans la fiche lot, mais sous une
// forme d'acte notarié : « 13(Bat A)-13bis(Local P)-17(Bat C)-19(Maison) avenue
// Carnot ». On garde ce libellé pour le conseiller et on en tire une adresse
// lisible (un seul numéro, sans mentions de bâtiments) pour le client et le plan.
function adresseLisible(brut: string) {
  const s = String(brut || '').replace(/\([^)]*\)/g, ' ').replace(/\s+/g, ' ').trim();
  const m = s.match(/^(\d+)\s*(?:(?:bis|ter|quater)\b)?\s*(?:[-–—/]\s*\d+\s*(?:bis|ter|quater)?\s*)*(.*)$/i);
  return m ? (m[1] + ' ' + m[2]).replace(/\s+/g, ' ').trim() : s;
}

// Coordonnées via la Base Adresse Nationale (service public, sans clé)
async function geocoder(adresse: string, zip: string, ville: string) {
  const q = [adresse, zip, ville].filter(Boolean).join(' ').trim();
  if (!q) return null;
  try {
    const r = await fetch('https://api-adresse.data.gouv.fr/search/?limit=1&q=' + encodeURIComponent(q));
    if (!r.ok) return null;
    const d = await r.json();
    const f = (d.features || [])[0];
    if (!f || !f.geometry || !Array.isArray(f.geometry.coordinates)) return null;
    const p = f.properties || {};
    // En dessous de 0,4 le résultat n'a plus rien à voir avec l'adresse demandée
    if (Number(p.score) < 0.4) return null;
    return {
      lat: f.geometry.coordinates[1],
      lon: f.geometry.coordinates[0],
      precision: p.type || '',      // housenumber = numéro exact, street = la voie
      label: p.label || ''
    };
  } catch (_) {
    return null;
  }
}

/* ===== Lignes de transport à proximité (30/09/2026) ==========================
   Demande d'Alex : montrer, à côté de chaque programme, les lignes de métro /
   RER / train / tram à proximité — jamais les bus — en reprenant la même base
   que la carte des programmes (GEO.transports.gares dans carte.html, rail
   uniquement). Plutôt que dupliquer ce jeu de données (1 240 gares) dans le
   code de la fonction, on le lit depuis un fichier séparé du repo (gares.json,
   déposé une seule fois à côté d'index.html — à re-déposer seulement si le
   réseau IDFM change, ce qui est rare), gardé en mémoire tant que l'instance
   de la fonction reste chaude. Même logique que nearGares() côté carte :
   rayon 2 km, une entrée par ligne (la gare la plus proche de cette ligne),
   4 résultats maximum. */
type Gare = { nom: string; ligne: string; lat: number; lng: number; col: string };
let garesCache: Gare[] | null = null;
let garesCacheA = 0;
async function chargerGares(): Promise<Gare[]> {
  if (garesCache && Date.now() - garesCacheA < 3600_000) return garesCache;
  try {
    const r = await fetch('https://raw.githubusercontent.com/alexandregrillault/glrimmobilier/main/gares.json', { signal: AbortSignal.timeout(5000) });
    if (r.ok) { garesCache = await r.json(); garesCacheA = Date.now(); }
  } catch (_) { /* on retombe sur la dernière liste connue en mémoire, ou aucune */ }
  return garesCache || [];
}
function distanceMetres(a: number, b: number, c: number, d: number) {
  const R = 6371e3, x = (c - a) * Math.PI / 180, y = (d - b) * Math.PI / 180 * Math.cos((a + c) / 2 * Math.PI / 180);
  return Math.sqrt(x * x + y * y) * R;
}
async function transportsProches(lat: number | null | undefined, lon: number | null | undefined) {
  if (lat == null || lon == null) return [];
  const gares = await chargerGares();
  const seen = new Set<string>();
  return gares
    .map((g) => ({ nom: g.nom, ligne: g.ligne, col: g.col, d: distanceMetres(lat, lon, g.lat, g.lng) }))
    .filter((x) => x.d < 2000)
    .sort((a, b) => a.d - b.d)
    .filter((x) => { const k = x.ligne + '|' + x.nom; if (seen.has(k)) return false; seen.add(k); return true; })
    .slice(0, 4)
    .map((x) => ({ ligne: x.ligne, gare: x.nom, distance: Math.round(x.d), couleur: x.col || '' }));
}

// Part de « fond uni » d'une image JPEG : pixels quasi blancs OU couleur dominante en aplat.
// 0 = vraie photo pleine de détails, 1 = page de texte (fond blanc classique
// ou fond de couleur, comme les pages de titre grises de certains promoteurs).
async function ratioFondUni(url: string): Promise<number> {
  try {
    const r = await fetch(url);
    if (!r.ok) return 1;
    const buf = new Uint8Array(await r.arrayBuffer());
    const { decode } = await import('npm:jpeg-js@0.4.4');
    const img: any = decode(buf, { useTArray: true, maxMemoryUsageInMB: 128, maxResolutionInMP: 12 });
    const totalPx = img.width * img.height;
    const pas = Math.max(1, Math.floor(totalPx / 40000)); // ~40 000 pixels échantillonnés
    const compte = new Map<number, number>();
    let blancs = 0, total = 0;
    for (let i = 0; i < totalPx; i += pas) {
      const o = i * 4;
      const r0 = img.data[o], g0 = img.data[o + 1], b0 = img.data[o + 2];
      if (r0 > 232 && g0 > 232 && b0 > 232) blancs++;
      // Quantification grossière : un aplat (fond gris d'une page de titre) concentre
      // ses pixels sur une seule case, une vraie photo se disperse sur des centaines
      const q = (Math.round(r0 / 24) << 10) | (Math.round(g0 / 24) << 5) | Math.round(b0 / 24);
      compte.set(q, (compte.get(q) || 0) + 1);
      total++;
    }
    if (!total) return 1;
    let dominante = 0;
    for (const n of compte.values()) if (n > dominante) dominante = n;
    return Math.max(blancs / total, dominante / total);
  } catch (_) {
    return 1;
  }
}

// Normalisation d'un texte en clé stable (sans accents, minuscules, tirets) —
// sert à fabriquer la clé de cache « promoteur:programme-ville » des documents
// Otaree mutualisés (30/09/2026).
function slugTexte(s: string) {
  return String(s || '')
    .normalize('NFD').replace(/\p{Diacritic}/gu, '')
    .toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/* ===== Base commune carte / Otaree (30/09/2026) ===============================
   Demande d'Alex : la carte et la feuille sélection doivent puiser dans la même
   base pour les programmes et leurs lots — quand un lien Otaree correspond à un
   programme déjà pigé, on réutilise (et on complète) documents_programme /
   documents_lot en clé réelle (pige_programmes.id / pige_lots.id), exactement
   comme le fait déjà extraireInterne() pour les lots venus de la carte, plutôt
   que la clé synthétique <promoteur>:<programme>-<ville> propre à Otaree. Sans
   correspondance sûre (promoteur + programme + ville normalisés, exactement —
   jamais d'approximation : un mauvais rapprochement mélangerait les documents
   de deux programmes différents), on retombe sur l'ancienne clé synthétique. */
function identite(s: string) {
  return String(s || '')
    .normalize('NFD').replace(/\p{Diacritic}/gu, '')
    .replace(/\([^)]*\)/g, ' ')   // « Pichet (RP) » -> le réseau n'est pas le nom du promoteur
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
function identiteNum(s: string) {
  return String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}
async function trouverProgrammeCarte(promoteur: string, programme: string, commune: string) {
  const idProg = identite(programme);
  const idCommune = identite(commune);
  const idProm = identite(promoteur);
  if (!idProg || !idCommune) return null;
  try {
    const { data } = await supabase.from('pige_programmes')
      .select('id, nom, ville, promoteur')
      .ilike('ville', '%' + commune.replace(/[%_]/g, '').trim().slice(0, 30) + '%');
    const candidats = (data || []).filter((r: any) =>
      identite(r.nom) === idProg && identite(r.ville) === idCommune && (!idProm || identite(r.promoteur) === idProm)
    );
    return candidats.length === 1 ? String(candidats[0].id) : null;
  } catch (_) { return null; }
}
async function trouverLotCarte(programmeId: string, numeroLot: string) {
  const idNum = identiteNum(numeroLot);
  if (!idNum) return null;
  try {
    const { data } = await supabase.from('pige_lots').select('id, n').eq('programme_id', programmeId);
    const candidats = (data || []).filter((r: any) => identiteNum(r.n) === idNum);
    return candidats.length === 1 ? String(candidats[0].id) : null;
  } catch (_) { return null; }
}

// La « Fiche lot » d'Otaree n'est pas une image : c'est une fiche structurée,
// accessible par une URL signée livrée avec la présentation. On y trouve la
// surface, l'étage, les annexes, l'adresse du programme et surtout les prix
// selon le régime de TVA.
async function detailsDuLot(presentation: any) {
  const files: any[] = Array.isArray(presentation?.presentationFiles) ? presentation.presentationFiles : [];
  const fiche = files.find((f) => f && f.type === 'property' && f.publicUrls && f.publicUrls.property);
  if (!fiche) return null;
  let p: any;
  try {
    const r = await fetch(fiche.publicUrls.property, { headers: { 'Accept': 'application/json' } });
    if (!r.ok) return null;
    p = await r.json();
  } catch (_) { return null; }

  const prog = p.program || {};
  const ville = [prog.addressCity, prog.addressZipCode].filter(Boolean).join(' ');
  const adresseBrute = String(prog.addressStreetAddress || (prog.address && prog.address.name) || '').trim();
  const adresse = adresseLisible(adresseBrute);
  const geo = adresse ? await geocoder(adresse, String(prog.addressZipCode || ''), String(prog.addressCity || '')) : null;

  // Un tarif par régime : droit commun (20 %), TVA réduite (5,5 %), LLI (10 %)…
  const prixOptions = (Array.isArray(p.prices) ? p.prices : [])
    .map((x: any) => ({
      tva: Number(x.vatRate),
      prix: Number(x.price),
      prixTexte: euros(x.price),
      prixM2: euros(x.squareMeterPrice),
      prixM2Pondere: euros(x.realSquareMeterPrice),
      lois: Array.isArray(x.laws) ? x.laws : [],
      loyer: x.monthlyRent ? euros(x.monthlyRent) : '',
      rendement: x.profitability ? String(x.profitability).replace('.', ',') + ' %' : ''
    }))
    .filter((x: any) => Number.isFinite(x.prix) && x.prix > 0)
    .sort((a: any, b: any) => b.tva - a.tva); // le régime plein d'abord, les avantages ensuite

  const reference = prixOptions.find((x: any) => x.tva >= 20) || prixOptions[0] || null;

  const annexes = (Array.isArray(p.annexes) ? p.annexes : []).map((a: any) => ({
    nom: String(a.name || '').trim(),
    type: ANNEXES[String(a.type || '').toUpperCase()] || String(a.type || ''),
    prix: Number(a.price) > 0 ? euros(a.price) : '',
    surface: Number(a.surface) > 0 ? m2(a.surface) : ''
  })).filter((a: any) => a.nom || a.type);

  const parking = annexes.find((a: any) => /parking|box|garage/i.test(a.type));

  return {
    ville,
    adresse,
    adresseBrute,
    codePostal: String(prog.addressZipCode || ''),
    commune: String(prog.addressCity || ''),
    geo,
    typologies: p.typology ? [String(p.typology)] : [],
    nature: p.natureLabel || '',
    surface: m2(p.surface),
    surfacePonderee: m2(p.weightedSurface),
    etage: p.floorLabel != null ? String(p.floorLabel) : '',
    terrasse: m2(p.terraceSurface),
    expo: (Array.isArray(p.exposures) ? p.exposures : []).map((e: string) => EXPOSITIONS[String(e).toUpperCase()] || e).join(', '),
    livraison: String(prog.deliveryQuarter || '').replace(/^(\d{4})T(\d)$/, '$1 T$2'),
    promoteur: (prog.displayedDeveloper && prog.displayedDeveloper.name) || (prog.developer && prog.developer.name) || '',
    programme: prog.name || '',
    annexes,
    parking: parking ? (parking.nom || parking.type) : '',
    prixOptions,
    prix: reference ? reference.prixTexte : ''
  };
}

// Extraction d'une fiche Otaree via leur API publique
async function extraireOtaree(lien: string) {
  const m = String(lien).match(/\/v\/([a-f0-9]{6,32})/i);
  if (!m) return { ok: false, error: 'Lien Otaree non reconnu' };
  let p: any;
  try {
    const r = await fetch('https://api.link-app.immo/public/presentations/' + m[1], { headers: { 'Accept': 'application/json' } });
    if (!r.ok) return { ok: false, error: 'Fiche introuvable (HTTP ' + r.status + ')' };
    p = await r.json();
  } catch (_) {
    return { ok: false, error: 'Otaree injoignable' };
  }
  const files: any[] = Array.isArray(p.presentationFiles) ? p.presentationFiles : [];
  const imgUrl = (f: any) => (f && f.file && f.file.urls) ? (f.file.urls.presentation || f.file.urls.large || f.file.urls.medium || '') : '';
  const urlAnalyse = (f: any) => (f && f.file && f.file.urls) ? (f.file.urls.medium || f.file.urls.large || f.file.urls.presentation || '') : '';
  // Fichier complet (PDF, toutes pages) plutôt que la preview image d'une seule
  // page — signé par Otaree, valable ~48h après cet appel API (30/09/2026).
  const urlOriginale = (f: any) => (f && f.file && f.file.urls) ? (f.file.urls.original || f.file.urls.download || '') : '';
  // Nombre de pages annoncé par Otaree (30/09/2026 soir) : le plan de masse et le
  // plan du lot sont, dans l'immense majorité des cas, un document d'une seule
  // page — Alex veut qu'ils restent une simple photo (comme avant), pas un PDF à
  // ouvrir. On ne bascule sur le PDF complet que si le document a vraiment
  // plusieurs pages (duplex, maison — cas signalé par Alex). La plaquette, elle,
  // est toujours hébergée en PDF complet (plusieurs pages, normal de la télécharger).
  const nbPages = (f: any) => {
    const n = Number(f && f.file && f.file.pageCount);
    return Number.isFinite(n) && n > 0 ? n : 1;
  };
  // Image par page d'un document (30/09/2026 soir) : Otaree fournit, pour un
  // document réellement multi-page, une image séparée par page (file.pages[]),
  // chacune avec sa propre URL — c'est ce qui permet d'afficher chaque niveau
  // d'un duplex/maison comme une photo à part, sans passer par un PDF à ouvrir
  // (demande d'Alex : « s'il existe plusieurs images pour un lot, les afficher »).
  const pagesImages = (f: any): string[] => {
    const pages: any[] = (f && f.file && Array.isArray(f.file.pages)) ? f.file.pages : [];
    if (pages.length > 1) {
      return pages.map((pg: any) => (pg && pg.urls) ? (pg.urls.large || pg.urls.medium || pg.urls.original || '') : '').filter(Boolean);
    }
    const u = imgUrl(f);
    return u ? [u] : [];
  };
  const nom = (f: any) => String(f && f.name || '').toLowerCase().trim();
  const nomEqPlan = (f: any) => f && f.type === 'file' && (nom(f) === 'plan' || (nom(f).includes('plan') && !nom(f).includes('masse')));
  // Tous les fichiers "plan" du lot (un duplex peut en avoir plusieurs : ex.
  // « Plan RDC » / « Plan R+1 » chez certains promoteurs, à défaut d'un seul
  // document à plusieurs pages) — plan reste le premier, pour compatibilité.
  const planFiles = files.filter(nomEqPlan);
  const plan = planFiles[0];
  const masse = files.find((f) => nom(f).includes('masse'));
  // Plaquette du programme (29/09/2026) : présente sous ce nom chez une partie
  // des promoteurs sur Otaree, au même titre que « Plan » et « Plan de masse ».
  const plaquette = files.find((f) => nom(f).includes('plaquette'));
  const cover = files.find((f) => f.type === 'coverPage');
  // Candidates "photo" : toutes les pages sauf plan, plan de masse, plaquette et page de garde
  const exclues = new Set([plan, masse, plaquette, cover].filter(Boolean).map((f: any) => imgUrl(f)));
  const candidates = files.filter((f) => { const u = imgUrl(f); return u && !exclues.has(u); }).slice(0, 4);
  // Analyse : on ne retient que les pages majoritairement visuelles (belle photo du programme).
  // Les pages à fond uni — blanches ou colorées (pages de titre) — sont écartées.
  // Si aucune ne passe, image reste vide → la page client affiche le logo GLR.
  const images: string[] = [];
  for (const f of candidates) {
    if (images.length >= 3) break;
    const ratio = await ratioFondUni(urlAnalyse(f));
    if (ratio < 0.55) images.push(imgUrl(f));
  }

  const details = await detailsDuLot(p);

  // ===== Hébergement permanent + mutualisation par programme (30/09/2026) =====
  // Les URLs Otaree (masse, plaquette, plan) expirent ~48h après cet appel API :
  // pour que le document reste accessible au-delà et pour éviter de re-stocker
  // la même plaquette à chaque sélection sur le même programme, on l'héberge une
  // bonne fois dans notre Storage (mêmes fonctions que pour la carte), retrouvé
  // ensuite via une clé « promoteur:programme-ville » dans documents_programme —
  // table déjà partagée avec la carte des programmes. Le plan du lot, lui, est
  // propre à chaque lot (pas de mutualisation) mais a le même besoin
  // d'hébergement permanent. Masse et plan : simple photo hébergée (comme avant)
  // sauf document réellement multi-page (duplex, maisons) où le PDF complet est
  // hébergé à la place ; plaquette : toujours le PDF complet.
  const promoteurSlug = details && details.promoteur ? slugTexte(details.promoteur) : '';
  const programmeSlug = details && details.programme ? slugTexte(details.programme) : '';
  const villeSlug = details && details.commune ? slugTexte(details.commune) : '';
  // Rapprochement avec un programme déjà pigé sur la carte (30/09/2026, voir plus
  // haut) : match sûr → clé réelle (pige_programmes.id), carte et feuille
  // sélection partagent alors le même document ; sinon clé synthétique Otaree.
  let clefProgramme = '';
  let idProgrammeCarte: string | null = null;
  if (details && details.programme && details.commune) {
    idProgrammeCarte = await trouverProgrammeCarte(details.promoteur || '', details.programme, details.commune);
  }
  if (idProgrammeCarte) {
    clefProgramme = idProgrammeCarte;
  } else if (programmeSlug && villeSlug) {
    clefProgramme = (promoteurSlug || 'otaree-sans-promoteur') + ':' + programmeSlug + '-' + villeSlug;
  }
  // Même logique pour le lot lui-même (numéro extrait de p.name, « Lot n°A-101 »).
  let clefLot = 'otaree:' + m[1];
  if (idProgrammeCarte) {
    const mLot = String(p.name || '').match(/lot\s*n?°?\s*([a-z0-9-]+)/i);
    if (mLot) {
      const idLotCarte = await trouverLotCarte(idProgrammeCarte, mLot[1]);
      if (idLotCarte) clefLot = idLotCarte;
    }
  }

  let masseUrl = imgUrl(masse);
  let plaquetteUrl = imgUrl(plaquette);
  let planUrl = imgUrl(plan);
  let planUrls: string[] = planUrl ? [planUrl] : [];

  try {
    const [cacheProgramme, cacheLot] = await Promise.all([
      clefProgramme
        ? supabase.from('documents_programme').select('plan_masse_url, plaquette_url').eq('programme_id', clefProgramme).maybeSingle()
        : Promise.resolve({ data: null } as any),
      planFiles.length
        ? supabase.from('documents_lot').select('plan_url, plan_urls').eq('lot_id', clefLot).maybeSingle()
        : Promise.resolve({ data: null } as any)
    ]);

    if (clefProgramme && masse) {
      if (cacheProgramme.data && cacheProgramme.data.plan_masse_url) {
        masseUrl = cacheProgramme.data.plan_masse_url;
      } else {
        const src = nbPages(masse) > 1 ? urlOriginale(masse) : imgUrl(masse);
        if (src) {
          const res = await importerDocDepuisUrl('programme', clefProgramme, 'masse', src, details && details.programme);
          if (res.ok) masseUrl = res.url as string;
        }
      }
    }

    if (clefProgramme && plaquette) {
      if (cacheProgramme.data && cacheProgramme.data.plaquette_url) {
        plaquetteUrl = cacheProgramme.data.plaquette_url;
      } else {
        const src = urlOriginale(plaquette);
        if (src) {
          const res = await importerDocDepuisUrl('programme', clefProgramme, 'plaquette', src, details && details.programme);
          if (res.ok) plaquetteUrl = res.url as string;
        }
      }
    }

    if (planFiles.length) {
      if (cacheLot.data && Array.isArray(cacheLot.data.plan_urls) && cacheLot.data.plan_urls.length) {
        planUrls = cacheLot.data.plan_urls;
        planUrl = planUrls[0];
      } else if (cacheLot.data && cacheLot.data.plan_url) {
        planUrl = cacheLot.data.plan_url;
        planUrls = [planUrl];
      } else {
        // Plusieurs images à héberger : soit plusieurs fichiers "Plan" distincts,
        // soit un seul fichier réellement multi-page (duplex, maison) — chaque
        // page devient une photo à part plutôt qu'un PDF à ouvrir.
        const multiImages = planFiles.length > 1 || planFiles.some((f) => nbPages(f) > 1);
        if (multiImages) {
          const brutes = planFiles.flatMap((f) => pagesImages(f));
          const items: { bytes: Uint8Array; contentType: string }[] = [];
          for (const u of brutes) {
            const got = await recupererOctets(u);
            if (got) items.push(got);
          }
          if (items.length) {
            const res = await stockerDocMulti('lot', clefLot, 'plan', items, details && details.programme);
            if (res.ok) { planUrl = res.url as string; planUrls = res.urls as string[]; }
          }
        } else {
          const src = imgUrl(plan);
          if (src) {
            const res = await importerDocDepuisUrl('lot', clefLot, 'plan', src, details && details.programme);
            if (res.ok) { planUrl = res.url as string; planUrls = [planUrl]; }
          }
        }
      }
    }
  } catch (_) {
    // Souci d'hébergement (réseau, fichier trop lourd...) : on garde les URLs de
    // preview déjà calculées ci-dessus (page 1 seulement, mais mieux que rien).
  }

  const transports = details && details.geo ? await transportsProches(details.geo.lat, details.geo.lon) : [];

  return {
    ok: true,
    titre: String(p.name || ''),
    lien,
    plan: planUrl,
    plans: planUrls,
    masse: masseUrl,
    plaquette: plaquetteUrl,
    image: images[0] || '',
    images,
    ...(details || {}),
    transports
  };
}

/* ===== Lien interne (22/09/2026) ============================================
   Pour un programme hors Otaree (issu de la pige), un lien "comme Otaree" peut
   être copié depuis la carte des programmes une fois ses documents complétés :
   https://.../glr/lot/<id du lot pigé>. Collé dans la même case que les liens
   Otaree, il est reconnu ici et répond exactement la même forme — rien à
   apprendre de plus côté vendeur, le reste du dashboard ne change pas.
   Source des données : pige_lots + pige_programmes (déjà pigés chaque semaine),
   complétés par documents_programme / documents_lot quand la pige n'a pas tout
   (plan de masse : jamais pigé ; plaquette : seulement chez quelques promoteurs
   comme Bouygues ; plan du lot : pigé chez la plupart des gros promoteurs mais
   pas tous).
   ============================================================================ */
const LIEN_INTERNE_RX = /\/glr\/lot\/([^/?#]+)/i;

function livraisonLisible(t: string) {
  // "T4 2026" (déjà lisible côté pige) -> inchangé ; on ne fait que garder le format existant
  return String(t || '').trim();
}

async function extraireInterne(lotId: string) {
  const { data: lot } = await supabase.from('pige_lots')
    .select('id, programme_id, n, type, typo, surf, etage, prix, prix_m2, st, data')
    .eq('id', lotId).maybeSingle();
  if (!lot) return { ok: false, error: 'Lot introuvable' };

  const { data: prog } = await supabase.from('pige_programmes')
    .select('id, nom, ville, cp, promoteur, livraison, lat, lng, data')
    .eq('id', lot.programme_id).maybeSingle();
  if (!prog) return { ok: false, error: 'Programme introuvable' };

  const dLot: any = (lot.data && typeof lot.data === 'object') ? lot.data : {};
  const dProg: any = (prog.data && typeof prog.data === 'object') ? prog.data : {};

  const [{ data: docsProg }, { data: docsLot }] = await Promise.all([
    supabase.from('documents_programme').select('plan_masse_url, plaquette_url').eq('programme_id', lot.programme_id).maybeSingle(),
    supabase.from('documents_lot').select('plan_url, plan_urls').eq('lot_id', lotId).maybeSingle()
  ]);

  // Le plan stocké chez nous (documents_lot, public) passe avant l'URL pigée :
  // celle-ci exige souvent la session de l'extranet et ne s'affiche pas chez
  // le client ni dans la vignette de la fiche (24/09/2026).
  const plan = String((docsLot && docsLot.plan_url) || dLot.plan || '');
  // plusieurs vues du même lot (30/09/2026, ex. duplex remonté depuis la carte) :
  // plan_urls si déjà rempli, sinon la seule URL disponible.
  const plans: string[] = (docsLot && Array.isArray(docsLot.plan_urls) && docsLot.plan_urls.length)
    ? docsLot.plan_urls
    : (plan ? [plan] : []);
  const masse = String((docsProg && docsProg.plan_masse_url) || '');
  const plaquette = String((docsProg && docsProg.plaquette_url) || dProg.plaquette || '');
  // Documents remis au client sur la feuille sélection (un bouton par document)
  const docs: { nom: string; url: string }[] = [];
  if (plans.length > 1) {
    plans.forEach((u, i) => docs.push({ nom: 'Plan du lot — vue ' + (i + 1), url: u }));
  } else if (plan) {
    docs.push({ nom: 'Plan du lot', url: plan });
  }
  if (masse) docs.push({ nom: 'Plan de masse', url: masse });
  if (plaquette) docs.push({ nom: 'Plaquette', url: plaquette });

  const expoBrut = String(dLot.expo || '').toUpperCase();
  const annexesTxt = String(dLot.annexes || '').trim();
  const parkingTxt = String(dLot.parkings || '').trim();

  const prixOptions: any[] = [];
  // Le prix pigé (lot.prix / data.prix) correspond au régime indiqué par data.tva — pas
  // forcément le droit commun (20 %) : plusieurs promoteurs (ex. Esprit Valmy, IRIS)
  // n'affichent que leur prix TVA réduite sur l'extranet, avec data.tva = 5.5 et pas de
  // prix20 du tout. Avant le 30/09/2026, ce prix réduit était quand même recopié comme
  // un faux "prix20" identique au prix réduit — Alex voyait alors les deux cases avec
  // exactement le même montant. On ne le recopie donc comme prix20 que si le régime pigé
  // n'est pas explicitement un régime réduit (tva absente/null = comportement historique
  // conservé, ou tva == 20).
  const tvaBrute = Number(dLot.tva);
  const regimeReduit = Number.isFinite(tvaBrute) && tvaBrute > 0 && tvaBrute < 20;
  const prix20 = Number(dLot.prix20 ?? (regimeReduit ? NaN : lot.prix));
  const prix55 = Number(dLot.prix55);
  if (Number.isFinite(prix20) && prix20 > 0) prixOptions.push({ tva: 20, prix: prix20, prixTexte: euros(prix20), prixM2: '', prixM2Pondere: '', lois: [], loyer: dLot.loyer ? euros(dLot.loyer) : '', rendement: dLot.renta ? String(dLot.renta).replace('.', ',') + ' %' : '' });
  if (Number.isFinite(prix55) && prix55 > 0) prixOptions.push({ tva: 5.5, prix: prix55, prixTexte: euros(prix55), prixM2: '', prixM2Pondere: '', lois: [], loyer: '', rendement: '' });

  // Adresse : celle imprimée par le promoteur sur son extranet, géocodée par la
  // pige. Fiable dès qu'elle existe et que le point n'est pas approximatif
  // (geo_approx = géocodage à la commune) — pas besoin de la faire confirmer par
  // le vendeur comme pour Otaree, qui se trompe parfois de voie (24/09/2026).
  const adresseProg = String(dProg.adresse || '').replace(/\s+/g, ' ').trim();
  const lat = typeof dProg.lat === 'number' ? dProg.lat : (typeof prog.lat === 'number' ? prog.lat : null);
  const lng = typeof dProg.lng === 'number' ? dProg.lng : (typeof prog.lng === 'number' ? prog.lng : null);
  const geoApprox = dProg.geo_approx === true || String(dProg.geo_approx) === 'true';
  const adresseFiable = !!adresseProg && lat != null && lng != null && !geoApprox;
  const geo = (lat != null && lng != null) ? {
    lat, lon: lng,
    precision: adresseFiable ? (/^\d/.test(adresseProg) ? 'housenumber' : 'street') : '',
    label: String(dProg.geo_label || '').replace(/\s*\(approx\)\s*$/, '') || [adresseProg, prog.cp, prog.ville].filter(Boolean).join(' ')
  } : null;
  const transports = geo ? await transportsProches(geo.lat, geo.lon) : [];

  return {
    ok: true,
    titre: String(prog.nom || '') + (lot.n ? ' - Lot ' + lot.n : ''),
    lien: 'https://hydqfbxdtpmbuooexekp.supabase.co/glr/lot/' + encodeURIComponent(lotId),
    lotId: String(lot.id),
    programmeId: String(prog.id),
    plan,
    plans,
    masse,
    image: '',
    images: [],
    ville: [prog.ville, prog.cp].filter(Boolean).join(' '),
    adresse: adresseProg,
    adresseBrute: adresseProg,
    adresseFiable,
    codePostal: String(prog.cp || ''),
    commune: String(prog.ville || ''),
    geo,
    typologies: lot.typo ? [String(lot.typo)] : [],
    nature: String(lot.type || ''),
    surface: m2(lot.surf),
    surfacePonderee: '',
    etage: lot.etage != null ? String(lot.etage) : (dLot.etage_raw || ''),
    terrasse: annexesTxt,
    expo: EXPOSITIONS[expoBrut] || String(dLot.expo || ''),
    livraison: livraisonLisible(dLot.livraison || prog.livraison || ''),
    promoteur: String(prog.promoteur || ''),
    programme: String(prog.nom || ''),
    annexes: [],
    parking: parkingTxt,
    prixOptions,
    prix: prixOptions[0] ? prixOptions[0].prixTexte : euros(lot.prix),
    plaquette,
    docs,
    transports
  };
}

// Enregistrement des documents d'un programme (plan de masse / plaquette) —
// une fois déposés, réutilisés pour tous les lots du programme. Écrit par la
// carte des programmes, qui n'a pas de session utilisateur : passe ici (clé
// service_role) plutôt que par une policy RLS ouverte au public.
async function enregistrerDocProgramme(programmeId: string, masse?: string, plaquette?: string) {
  const id = String(programmeId || '').trim();
  const m = typeof masse === 'string' ? masse.trim() : '';
  const p = typeof plaquette === 'string' ? plaquette.trim() : '';
  if (!id || (!m && !p)) return { ok: false, error: 'invalide' };
  if ((m && !/^https?:\/\//i.test(m)) || (p && !/^https?:\/\//i.test(p))) return { ok: false, error: 'lien_invalide' };
  const patch: Record<string, unknown> = { programme_id: id, maj_le: new Date().toISOString() };
  if (m) patch.plan_masse_url = m;
  if (p) patch.plaquette_url = p;
  const { error } = await supabase.from('documents_programme').upsert(patch, { onConflict: 'programme_id' });
  return { ok: !error };
}

// Enregistrement du plan d'un lot (quand la pige ne l'a pas)
async function enregistrerDocLot(lotId: string, plan?: string) {
  const id = String(lotId || '').trim();
  const url = typeof plan === 'string' ? plan.trim() : '';
  if (!id || !url) return { ok: false, error: 'invalide' };
  if (!/^https?:\/\//i.test(url)) return { ok: false, error: 'lien_invalide' };
  const { error } = await supabase.from('documents_lot').upsert({ lot_id: id, plan_url: url, maj_le: new Date().toISOString() }, { onConflict: 'lot_id' });
  return { ok: !error };
}

/* ===== Dépôt de fichier depuis la carte (22/09/2026) =========================
   La carte n'a pas de session : le vendeur ne peut pas uploader directement
   dans Storage avec son propre jeton (comme index.html le fait ailleurs pour
   les plans/documents de sélection). Le fichier (PDF) est donc envoyé ici en
   base64 dans le corps de la requête, stocké dans le bucket public `docs`
   (déjà utilisé côté sélection) via la clé service_role, puis son URL publique
   est enregistrée dans documents_programme / documents_lot comme avant.
   Chemin fixe par programme/lot/champ (pas d'horodatage) : « Modifier » écrase
   proprement l'ancien fichier au lieu d'en accumuler de nouveaux.
   ============================================================================ */
const SUPABASE_URL_ENV = Deno.env.get('SUPABASE_URL')!;
const DOC_MAX_OCTETS = 50 * 1024 * 1024; // 50 Mo (20 Mo jusqu'au 23/09/2026 : quelques plaquettes promoteur dépassaient)

function cheminDoc(cible: 'programme' | 'lot', id: string, champ: string, ext: string) {
  const sur = String(id).replace(/[^a-zA-Z0-9._-]/g, '_');
  return 'documents/' + cible + '/' + sur + '/' + champ + '.' + ext;
}

// Nom « propre » du fichier proposé au téléchargement (n'affecte pas le chemin de
// stockage, qui reste fixe par programme/lot/champ — seulement ce que le navigateur
// suggère comme nom quand on ouvre/enregistre le document). Convention Alex (22/09/2026) :
// « PDM <nom du programme> » pour le plan de masse, « Plaquette <nom du programme> ».
function nomFichierAffiche(champ: string, nom: string | undefined, ext: string) {
  const prefixe = champ === 'masse' ? 'PDM' : (champ === 'plaquette' ? 'Plaquette' : 'Plan');
  const base = (nom && nom.trim()) ? (prefixe + ' ' + nom.trim()) : prefixe;
  return base.replace(/[\/\\:*?"<>|]/g, ' ').replace(/\s+/g, ' ').trim() + '.' + ext;
}

// Détection du format réel à partir des octets (signature), jamais du nom de fichier
// ou de l'en-tête content-type envoyés par la source (peu fiables). Le plan de masse
// est parfois un PDF, parfois une simple image (constaté chez Bouygues, 23/09/2026 :
// image JPEG à un chemin dédié /images/bi_prg_plan_<code>.jpg) — la plaquette et le
// plan de lot restent en pratique toujours des PDF, mais la détection est la même
// pour les trois champs : on stocke ce qu'on trouve, jamais une page d'erreur/de
// connexion renvoyée à la place du document.
function detecterFormat(bytes: Uint8Array): { ext: string; ct: string } | null {
  if (bytes.length > 4 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) {
    return { ext: 'pdf', ct: 'application/pdf' };
  }
  if (bytes.length > 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
    return { ext: 'jpg', ct: 'image/jpeg' };
  }
  if (bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
    return { ext: 'png', ct: 'image/png' };
  }
  return null;
}

// Écriture commune (stockage + base) une fois qu'on a les octets du document, que
// celui-ci vienne d'un dépôt de fichier (deposerDoc) ou d'une récupération d'URL
// côté serveur (importerDocDepuisUrl).
async function stockerDoc(cible: 'programme' | 'lot', idOk: string, champ: string, bytes: Uint8Array, contentType: string, nom?: string) {
  const format = detecterFormat(bytes);
  if (!format) return { ok: false, error: 'format_non_reconnu' };

  const chemin = cheminDoc(cible, idOk, champ, format.ext);
  const { error: erreurStockage } = await supabase.storage.from('docs').upload(chemin, bytes, {
    contentType: format.ct,
    upsert: true
  });
  if (erreurStockage) return { ok: false, error: 'echec_stockage' };

  const nomFichier = nomFichierAffiche(champ, nom, format.ext);
  // Correctif 30/09/2026 : ?download= force un Content-Disposition: attachment.
  // Pour un PDF ouvert directement (target=_blank côté selection.html, ou dans
  // l'iframe d'aperçu de la carte), ça fait échouer l'affichage : le navigateur
  // propose juste d'enregistrer le fichier au lieu de le montrer. On ne force le
  // téléchargement que pour les images (bouton "Télécharger" dédié, qui en a
  // besoin pour marcher en cross-origin) ; un PDF reste consultable en ligne, et
  // peut toujours être enregistré via le bouton de la visionneuse PDF du navigateur.
  const publicUrl = SUPABASE_URL_ENV + '/storage/v1/object/public/docs/' + chemin
    + (format.ext === 'pdf' ? '' : ('?download=' + encodeURIComponent(nomFichier)));
  if (cible === 'programme') {
    const patch: Record<string, unknown> = { programme_id: idOk, maj_le: new Date().toISOString() };
    patch[champ === 'masse' ? 'plan_masse_url' : 'plaquette_url'] = publicUrl;
    const { error } = await supabase.from('documents_programme').upsert(patch, { onConflict: 'programme_id' });
    if (error) return { ok: false, error: 'echec_base' };
  } else {
    // plan_urls (30/09/2026) : toujours tenu à jour, même pour un dépôt simple à
    // une seule image — la feuille/le dashboard n'ont qu'une seule forme à lire.
    const { error } = await supabase.from('documents_lot').upsert({ lot_id: idOk, plan_url: publicUrl, plan_urls: [publicUrl], maj_le: new Date().toISOString() }, { onConflict: 'lot_id' });
    if (error) return { ok: false, error: 'echec_base' };
  }
  return { ok: true, url: publicUrl, nomFichier };
}

async function deposerDoc(cible: string, id: string, champ: string, dataBase64: string, contentType?: string, nom?: string) {
  const idOk = String(id || '').trim();
  if ((cible !== 'programme' && cible !== 'lot') || !idOk || !dataBase64) return { ok: false, error: 'invalide' };
  if (cible === 'programme' && champ !== 'masse' && champ !== 'plaquette') return { ok: false, error: 'champ_invalide' };
  if (cible === 'lot' && champ !== 'plan') return { ok: false, error: 'champ_invalide' };

  let bytes: Uint8Array;
  try {
    const bin = atob(dataBase64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch (_) {
    return { ok: false, error: 'fichier_illisible' };
  }
  if (!bytes.length) return { ok: false, error: 'fichier_vide' };
  if (bytes.length > DOC_MAX_OCTETS) return { ok: false, error: 'fichier_trop_lourd' };

  return await stockerDoc(cible as 'programme' | 'lot', idOk, champ, bytes, contentType || 'application/pdf', nom);
}

/* ===== Import direct depuis une URL, côté serveur (22/09/2026) ================
   Pour le chantier « aller chercher plan de masse + plaquette pour tous les
   programmes en mandat » : beaucoup de plaquettes sont déjà pigées sous forme de
   lien PDF direct chez le promoteur (pige_programmes.data.plaquette). Plutôt que
   de faire transiter le fichier par le navigateur d'Alex (lent, gros volumes),
   le serveur va chercher l'URL lui-même — le fichier ne transite jamais par
   l'environnement de Claude ni par la conversation.
   ============================================================================ */
async function importerDocDepuisUrl(cible: string, id: string, champ: string, sourceUrl: string, nom?: string) {
  const idOk = String(id || '').trim();
  const url = String(sourceUrl || '').trim();
  if ((cible !== 'programme' && cible !== 'lot') || !idOk || !url) return { ok: false, error: 'invalide' };
  if (!/^https?:\/\//i.test(url)) return { ok: false, error: 'lien_invalide' };
  if (cible === 'programme' && champ !== 'masse' && champ !== 'plaquette') return { ok: false, error: 'champ_invalide' };
  if (cible === 'lot' && champ !== 'plan') return { ok: false, error: 'champ_invalide' };

  let bytes: Uint8Array;
  let contentType = 'application/pdf';
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(25000), headers: { 'Accept': 'application/pdf,*/*' } });
    if (!r.ok) return { ok: false, error: 'source_inaccessible' };
    const ct = r.headers.get('content-type') || '';
    if (ct) contentType = ct.split(';')[0].trim();
    bytes = new Uint8Array(await r.arrayBuffer());
  } catch (_) {
    return { ok: false, error: 'source_injoignable' };
  }
  if (!bytes.length) return { ok: false, error: 'fichier_vide' };
  if (bytes.length > DOC_MAX_OCTETS) return { ok: false, error: 'fichier_trop_lourd' };

  return await stockerDoc(cible as 'programme' | 'lot', idOk, champ, bytes, contentType, nom);
}

/* ===== Plusieurs images pour un même champ (30/09/2026) =======================
   Un duplex/une maison peut avoir plusieurs plans (un par niveau) : chaque image
   est récupérée et hébergée séparément (documents/lot/<id>/plan-1.<ext>,
   plan-2.<ext>…), puis rangée dans documents_lot.plan_urls (tableau) — plan_url
   garde la première, pour tout ce qui ne lit encore qu'une seule image (carte,
   ancien code). Réutilise la détection de format et le chemin de rangement de
   stockerDoc/cheminDoc, sans dupliquer l'écriture programme (jamais utilisé
   pour cible='programme' à ce jour — plan de masse reste toujours une image). */
async function recupererOctets(url: string): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(25000), headers: { 'Accept': 'image/*,application/pdf,*/*' } });
    if (!r.ok) return null;
    const ct = r.headers.get('content-type') || 'application/octet-stream';
    const bytes = new Uint8Array(await r.arrayBuffer());
    if (!bytes.length || bytes.length > DOC_MAX_OCTETS) return null;
    return { bytes, contentType: ct.split(';')[0].trim() };
  } catch (_) { return null; }
}
async function stockerDocMulti(cible: 'lot', idOk: string, champ: 'plan', items: { bytes: Uint8Array; contentType: string }[], nom?: string) {
  const urls: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const format = detecterFormat(items[i].bytes);
    if (!format) continue;
    const suffixe = items.length > 1 ? (champ + '-' + (i + 1)) : champ;
    const chemin = cheminDoc(cible, idOk, suffixe, format.ext);
    const { error } = await supabase.storage.from('docs').upload(chemin, items[i].bytes, { contentType: format.ct, upsert: true });
    if (error) continue;
    const nomAffiche = nom ? (items.length > 1 ? nom + ' - vue ' + (i + 1) : nom) : undefined;
    const nomFichier = nomFichierAffiche(champ, nomAffiche, format.ext);
    urls.push(SUPABASE_URL_ENV + '/storage/v1/object/public/docs/' + chemin
      + (format.ext === 'pdf' ? '' : ('?download=' + encodeURIComponent(nomFichier))));
  }
  if (!urls.length) return { ok: false, error: 'echec_stockage' };
  const { error } = await supabase.from('documents_lot').upsert({
    lot_id: idOk, plan_url: urls[0], plan_urls: urls, maj_le: new Date().toISOString()
  }, { onConflict: 'lot_id' });
  if (error) return { ok: false, error: 'echec_base' };
  return { ok: true, url: urls[0], urls };
}

const estExpiree = (sel: any) => !!(sel.expires_at && new Date(sel.expires_at).getTime() < Date.now());
const prenomDe = (nom: string) => {
  const p = String(nom || '').trim().split(/\s+/)[0] || '';
  // Nom issu d'un email (tout en minuscules) : on met au moins une majuscule
  return p && p === p.toLowerCase() ? p.charAt(0).toUpperCase() + p.slice(1) : p;
};
// « Monsieur Dupont », « Camille Durand » ou rien (page retombe sur le prénom) —
// réglage posé une fois sur la fiche client (civilite + mode_adresse), snapshoté
// à la création de la sélection comme le reste de `biens` (01/10/2026, demande
// d'Alex : le commercial n'a plus à le ressaisir à chaque sélection).
const salutationDe = (sel: any) => {
  const civ = String(sel?.client_civilite || '').trim();
  const nomF = String(sel?.client_nom_famille || '').trim();
  const mode = String(sel?.client_mode_adresse || '').trim();
  if (mode === 'prenom_nom') {
    const p = prenomDe(sel?.client_nom || '');
    return p && nomF ? p + ' ' + nomF : '';
  }
  // Comportement historique (mode absent = anciennes sélections, ou 'civilite_nom')
  return civ && nomF ? civ + ' ' + nomF : '';
};

// ---------- Régimes fiscaux montrés au client ----------
// Ne jamais afficher sur la sélection :
//   - TVA 10 % (LLI) et TVA 0 % (LMNP) : dispositifs que GLR ne commercialise pas
//   - TVA 5,5 % : seulement si le conseiller a marqué le client « non éligible »
//   - taux inconnu (< 0 : ancien / réhabilité) : pas de bloc de régime, la page
//     retombe alors sur le prix simple du lot
/* ===== Documents des lots venus de la carte, relus à chaque ouverture ========
   Un lot ajouté depuis la carte garde ses identifiants pigés (_cartePigeId,
   _carteProgrammeId). Plaquette, plan de masse et plan du lot sont relus dans
   documents_programme / documents_lot au moment où le client ouvre sa page :
   un document déposé APRÈS l'envoi de la sélection (depuis la fiche client ou
   la carte) apparaît donc sans rien refaire (24/09/2026, demande d'Alex : « en
   automatique »). Les lots Otaree ne sont pas concernés.
   ============================================================================ */
async function documentsCarte(biens: any[]) {
  const progs = new Set<string>(), lots = new Set<string>();
  for (const b of biens) {
    if (!b || typeof b !== 'object') continue;
    if (b._carteProgrammeId) progs.add(String(b._carteProgrammeId));
    if (b._cartePigeId) lots.add(String(b._cartePigeId));
  }
  const out = { progs: new Map<string, any>(), lots: new Map<string, any>() };
  if (!progs.size && !lots.size) return out;
  try {
    const [rp, rl] = await Promise.all([
      progs.size ? supabase.from('documents_programme').select('programme_id, plan_masse_url, plaquette_url').in('programme_id', [...progs]) : Promise.resolve({ data: [] as any[] }),
      lots.size ? supabase.from('documents_lot').select('lot_id, plan_url, plan_urls').in('lot_id', [...lots]) : Promise.resolve({ data: [] as any[] })
    ]);
    for (const r of (rp.data || [])) out.progs.set(String(r.programme_id), r);
    for (const r of (rl.data || [])) out.lots.set(String(r.lot_id), r);
  } catch (_) { /* la page se contente alors des documents figés à l'envoi */ }
  return out;
}

function completerDocsCarte(b: any, docs: { progs: Map<string, any>; lots: Map<string, any> }) {
  if (!b || typeof b !== 'object' || (!b._carteProgrammeId && !b._cartePigeId)) return b;
  const dp = b._carteProgrammeId ? docs.progs.get(String(b._carteProgrammeId)) : null;
  const dl = b._cartePigeId ? docs.lots.get(String(b._cartePigeId)) : null;
  if (dp && dp.plan_masse_url) b.masse = String(dp.plan_masse_url);
  if (dp && dp.plaquette_url) b.plaquette = String(dp.plaquette_url);
  if (dl && dl.plan_url && !b.plan) b.plan = String(dl.plan_url);
  if (dl && Array.isArray(dl.plan_urls) && dl.plan_urls.length) b.plans = dl.plan_urls;
  else if (b.plan && (!Array.isArray(b.plans) || !b.plans.length)) b.plans = [b.plan];
  const liste: { nom: string; url: string }[] = [];
  const vuesPlan: string[] = Array.isArray(b.plans) && b.plans.length ? b.plans : (b.plan ? [String(b.plan)] : []);
  if (vuesPlan.length > 1) {
    vuesPlan.forEach((u, i) => liste.push({ nom: 'Plan du lot — vue ' + (i + 1), url: String(u) }));
  } else if (b.plan) {
    liste.push({ nom: 'Plan du lot', url: String(b.plan) });
  }
  if (b.masse) liste.push({ nom: 'Plan de masse', url: String(b.masse) });
  if (b.plaquette) liste.push({ nom: 'Plaquette', url: String(b.plaquette) });
  b.docs = liste;
  return b;
}

function filtrerRegimes(biens: any[], tvaReduiteExclue: boolean) {
  return biens.map((b: any) => {
    if (!b || typeof b !== 'object' || !Array.isArray(b.prixOptions) || !b.prixOptions.length) return b;
    const gardes = b.prixOptions.filter((o: any) => {
      const t = Number(o && o.tva);
      if (!Number.isFinite(t) || t < 0) return false;
      if (t === 0 || t === 10) return false;
      if (t === 5.5 && tvaReduiteExclue) return false;
      return true;
    });
    // Un lot ne doit jamais perdre son prix : si plus aucun régime n'est affichable,
    // la page utilise le champ `prix` (tarif de référence, droit commun).
    const reference = b.prixOptions.find((o: any) => Number(o && o.tva) >= 20) || b.prixOptions[0];
    const prix = b.prix || (reference && reference.prixTexte) || '';
    return { ...b, prixOptions: gardes, prix };
  });
}

// Le conseiller a-t-il marqué ce client comme non éligible à la TVA réduite ?
async function tvaReduiteExclue(contactId: string | null) {
  if (!contactId) return false;
  try {
    const { data } = await supabase.from('contacts').select('qualif').eq('id', contactId).maybeSingle();
    const q: any = data && data.qualif;
    return String((q && q.tva_reduite) || '') === 'non';
  } catch (_) {
    return false; // en cas de doute on n'enlève rien de plus que les régimes non commercialisés
  }
}

// Tableau « Comment on y arrive » du simulateur (lignes libellé/montant + note),
// enregistré avec la simulation et montré tel quel sur la feuille sélection —
// revenus retenus et apport compris, décision d'Alex du 02/10/2026 (le client
// voit son propre montage). Lignes bornées, texte brut uniquement.
function montageSur(x: any) {
  if (!x || typeof x !== 'object' || !Array.isArray(x.lignes)) return null;
  const lignes = x.lignes.slice(0, 20).map((r: any) => ({
    l: typeof r?.l === 'string' ? r.l.slice(0, 220) : '',
    v: typeof r?.v === 'string' ? r.v.slice(0, 60) : '',
    c: r?.c === 'sub' || r?.c === 'total' ? r.c : ''
  })).filter((r: any) => r.l && r.v);
  if (!lignes.length) return null;
  return {
    lignes,
    note: typeof x.note === 'string' ? x.note.slice(0, 600) : '',
    budgetAvec: Number.isFinite(Number(x.budgetAvec)) ? Math.round(Number(x.budgetAvec)) : null,
    budgetSans: Number.isFinite(Number(x.budgetSans)) ? Math.round(Number(x.budgetSans)) : null
  };
}

// Objectif du client sous son budget maximum (mensualité souhaitée ou budget
// visé), avec la part de sa capacité d'emprunt qu'il représente — montré sous
// le budget maximum sur la feuille sélection (06/10/2026). Nombres seulement.
function objectifSur(x: any) {
  if (!x || typeof x !== 'object') return null;
  const n = (v: any) => (v !== null && v !== undefined && Number.isFinite(Number(v))) ? Math.round(Number(v)) : null;
  const budget = n(x.budget), mensualite = n(x.mensualite), mensualiteMax = n(x.mensualiteMax), pct = n(x.pct);
  if (!budget || budget <= 0 || !mensualite || mensualite <= 0 || !mensualiteMax || mensualiteMax <= 0) return null;
  return { type: x.type === 'mensualite' ? 'mensualite' : 'prix', budget, mensualite, mensualiteMax, pct };
}

// État complet du simulateur (réponses du formulaire), gardé pour que le vendeur
// retrouve les réponses à la prochaine ouverture. Jamais renvoyé à la page publique.
function etatSur(x: any) {
  if (!x || typeof x !== 'object' || Array.isArray(x)) return null;
  try { return JSON.stringify(x).length <= 12000 ? x : null; } catch (_) { return null; }
}

// Ce que chaque aide apporte sur un lot, en euros (11/11/2026, demande d'Alex) :
// tva = baisse du prix, ptz / pal / ppl = intérêts évités (montant = somme prêtée).
const GAINS_AIDES = ['tva', 'ptz', 'pal', 'ppl'];
function gainsSur(x: any) {
  if (!Array.isArray(x)) return [];
  return x.slice(0, 6).map((g: any) => ({
    a: GAINS_AIDES.includes(g?.a) ? g.a : '',
    v: Number.isFinite(Number(g?.v)) ? Math.round(Number(g.v)) : 0,
    montant: Number.isFinite(Number(g?.montant)) ? Math.round(Number(g.montant)) : null
  })).filter((g: any) => g.a && g.v > 0);
}

// Loyer actuel du client locataire (euros par mois), pour l'écart avec la
// mensualité de chaque lot sur la feuille sélection (11/11/2026). Nul sinon.
function loyerSur(v: any) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 && n < 20000 ? Math.round(n) : null;
}

// Dernier résumé de simulation de financement (montré côté client, sur la
// feuille sélection). Le profil détaillé (revenus, apport, durée) n'est
// jamais renvoyé à la page publique — seul le résultat compte pour le client,
// plus le tableau du montage (`montage`) quand la simulation l'a enregistré.
async function derniereSimulation(contactId: string | null) {
  if (!contactId) return null;
  try {
    const { data } = await supabase.from('contacts').select('simulations').eq('id', contactId).maybeSingle();
    const liste: any[] = Array.isArray(data && data.simulations) ? data.simulations : [];
    const s = liste[0];
    if (!s) return null;
    return {
      date: s.date || null,
      budgetMax: Number.isFinite(Number(s.budgetMax)) ? Number(s.budgetMax) : null,
      montage: montageSur(s.montage),
      objectif: objectifSur(s.objectif),
      loyerActuel: loyerSur(s.loyerActuel),
      lots: Array.isArray(s.lots) ? s.lots.map((l: any) => ({
        cle: String(l?.cle || ''),
        mensualite: Number.isFinite(Number(l?.mensualite)) ? Number(l.mensualite) : null,
        economie: Number.isFinite(Number(l?.economie)) ? Number(l.economie) : null,
        gains: gainsSur(l?.gains),
        eligible: typeof l?.eligible === 'boolean' ? l.eligible : null
      })).filter((l: any) => l.cle) : []
    };
  } catch (_) {
    return null;
  }
}

// Créneaux encore libres du conseiller, dans la fenêtre visible. Chaque créneau
// porte `duree_max` : le temps libre d'affilée à partir de son début (créneaux
// contigus enchaînés), pour que la page ne propose la visio de 30 min que là
// où elle tient vraiment. Créneaux de 10 min : jusqu'à 2 500 sur trois semaines.
async function creneauxDisponibles(vendeur: string) {
  if (!vendeur) return [];
  const fin = new Date(Date.now() + RDV_JOURS_VISIBLES * 86400000).toISOString();
  const { data } = await supabase.from('creneaux')
    .select('id, debut, fin, mode, lieu')
    .eq('vendeur', vendeur)
    .eq('statut', 'libre')
    .gt('debut', new Date().toISOString())
    .lt('debut', fin)
    .order('debut', { ascending: true })
    .limit(2500);
  const liste = (data || []).map((c: any) => ({ ...c, duree_max: 0 }));
  const finDe = new Map<number, number>(); // début (ms) -> fin la plus lointaine parmi les créneaux qui y commencent
  liste.forEach((c: any) => {
    const d = new Date(c.debut).getTime(), f = new Date(c.fin).getTime();
    if (!finDe.has(d) || finDe.get(d)! < f) finDe.set(d, f);
  });
  liste.forEach((c: any) => {
    const d = new Date(c.debut).getTime();
    let cur = new Date(c.fin).getTime();
    let garde = 0;
    while (finDe.has(cur) && garde++ < 20) cur = finDe.get(cur)!;
    c.duree_max = Math.round((cur - d) / 60000);
  });
  return liste;
}

// Créneaux proposés spécifiquement à ce client après un refus du conseiller
async function creneauxProposes(token: string) {
  const { data } = await supabase.from('creneaux')
    .select('id, debut, fin, mode, lieu')
    .eq('selection_token', token)
    .eq('statut', 'propose')
    .gt('debut', new Date().toISOString())
    .order('debut', { ascending: true })
    .limit(10);
  return data || [];
}

// Réservation d'un créneau. Avec un format (visio 30 / appel 10), on ne bloque
// que la durée réelle via reserver_duree ; sans format (ancienne page en cache),
// on prend le créneau tel quel.
async function reserverCreneau(o: { id: string; format: string | null; contact: string | null; token: string; nom: string; message: string }) {
  if (o.format) {
    const f = FORMATS[o.format];
    const { data, error } = await supabase.rpc('reserver_duree', {
      p_id: o.id, p_duree: f.duree, p_mode: f.mode,
      p_contact: o.contact, p_token: o.token, p_nom: o.nom, p_message: o.message
    });
    const c = Array.isArray(data) ? data[0] : data;
    return (error || !c || !c.id) ? null : c;
  }
  const { data, error } = await supabase.rpc('reserver_creneau', {
    p_id: o.id, p_contact: o.contact, p_token: o.token, p_nom: o.nom, p_message: o.message
  });
  const c = Array.isArray(data) ? data[0] : data;
  return (error || !c || !c.id) ? null : c;
}

// Le client a choisi son jour : la relance du vendeur se recale dessus, pour ne pas
// se retrouver avec un rappel la veille ET un rendez-vous le surlendemain.
// Sauf si la fiche porte une activité de préparation — un intitulé, datée avant
// le rendez-vous (« Faire la sélection » la veille) : elle reste en place, le
// rendez-vous vit de toute façon dans le planning (08/09/2026).
async function calerRappelSurLeRdv(contactId: string | null, debut: string) {
  if (!contactId || !debut) return;
  try {
    const jour = new Date(debut).toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });
    const { data: c } = await supabase.from('contacts').select('rappel_le, rappel_titre').eq('id', contactId).maybeSingle();
    if (c && c.rappel_le && c.rappel_titre && String(c.rappel_le) < jour) return;
    await supabase.from('contacts').update({ rappel_le: jour }).eq('id', contactId);
  } catch (_) { /* le rendez-vous reste pris même si la relance ne bouge pas */ }
}

// Cumul du temps de lecture : {total, biens:{index: secondes}}
function fusionnerTemps(actuel: any, ajout: any, nbBiens: number) {
  const base = (actuel && typeof actuel === 'object') ? actuel : {};
  const biens: Record<string, number> = (base.biens && typeof base.biens === 'object') ? { ...base.biens } : {};
  const borne = (v: unknown) => {
    const n = Math.floor(Number(v));
    return Number.isFinite(n) && n > 0 ? Math.min(n, 600) : 0; // garde-fou : 10 min max par envoi
  };
  let ajoutTotal = borne(ajout && ajout.total);
  const parBien = (ajout && ajout.biens && typeof ajout.biens === 'object') ? ajout.biens : {};
  for (const k of Object.keys(parBien)) {
    const i = parseInt(k, 10);
    if (!Number.isInteger(i) || i < 0 || i >= Math.max(nbBiens, 1)) continue;
    const s = borne(parBien[k]);
    if (s) biens[String(i)] = (Number(biens[String(i)]) || 0) + s;
  }
  if (!ajoutTotal) ajoutTotal = 0;
  return { total: (Number(base.total) || 0) + ajoutTotal, biens };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const url = new URL(req.url);

  let body: any = null;
  if (req.method === 'POST') {
    try { body = await req.json(); } catch (_) { body = {}; }
    // Extraction Otaree OU lien interne : pas besoin de token de sélection
    if (body && body.action === 'extraire') {
      const lien = String(body.lien || '');
      const mInterne = lien.match(LIEN_INTERNE_RX);
      return json(mInterne ? await extraireInterne(decodeURIComponent(mInterne[1])) : await extraireOtaree(lien));
    }
    // Documents d'un programme hors Otaree (plan de masse / plaquette), déposés
    // depuis la carte — pas de session utilisateur là-bas, d'où le passage ici.
    if (body && body.action === 'doc_programme') {
      return json(await enregistrerDocProgramme(body.programme_id, body.plan_masse_url, body.plaquette_url));
    }
    // Plan d'un lot hors Otaree, quand la pige ne l'a pas
    if (body && body.action === 'doc_lot') {
      return json(await enregistrerDocLot(body.lot_id, body.plan_url));
    }
    // Dépôt d'un vrai fichier (PDF, en base64) depuis la carte : plan de masse /
    // plaquette d'un programme, ou plan d'un lot.
    if (body && body.action === 'doc_upload') {
      return json(await deposerDoc(body.target, body.id, body.field, body.data_base64, body.content_type, body.nom));
    }
    // Import direct depuis une URL déjà connue (ex. plaquette déjà pigée chez le
    // promoteur) : le serveur va chercher le fichier lui-même, rien ne transite
    // par Claude ni par le navigateur.
    if (body && body.action === 'doc_import_url') {
      return json(await importerDocDepuisUrl(body.target, body.id, body.field, body.source_url, body.nom));
    }
  }

  const parts = url.pathname.split('/').filter(Boolean);
  const last = parts[parts.length - 1] || '';
  const token = url.searchParams.get('t') || (last !== 'selection' ? last : '');
  if (!token || !/^[a-f0-9]{6,32}$/i.test(token)) {
    if (req.method === 'POST' || url.searchParams.get('data') === '1') return json({ ok: false, error: 'lien_invalide' }, 404);
    return new Response('Lien invalide', { status: 404, headers: CORS });
  }

  const { data: sel, error } = await supabase.from('selections')
    .select('token, contact_id, client_nom, client_civilite, client_nom_famille, client_mode_adresse, vendeur, message, biens, avis, opened_at, created_at, expires_at, temps, visites, dernier_vu, maj_at')
    .eq('token', token).maybeSingle();
  if (error || !sel) {
    if (req.method === 'POST' || url.searchParams.get('data') === '1') return json({ ok: false, error: 'lien_invalide' }, 404);
    return new Response('Lien invalide', { status: 404, headers: CORS });
  }

  if (req.method === 'POST') {
    if (body.action === 'ouvert') {
      const maj: Record<string, unknown> = { dernier_vu: new Date().toISOString(), visites: (Number(sel.visites) || 0) + 1 };
      if (!sel.opened_at) maj.opened_at = new Date().toISOString();
      await supabase.from('selections').update(maj).eq('token', token);
      return json({ ok: true });
    }

    // Temps de lecture envoyé par la page client (battements réguliers + fermeture d'onglet)
    if (body.action === 'temps') {
      const nbBiens = Array.isArray(sel.biens) ? sel.biens.length : 0;
      const temps = fusionnerTemps(sel.temps, body, nbBiens);
      await supabase.from('selections').update({ temps, dernier_vu: new Date().toISOString() }).eq('token', token);
      return json({ ok: true });
    }

    if (estExpiree(sel)) return json({ ok: false, error: 'expire' }, 410);
    const avis = (sel.avis && typeof sel.avis === 'object') ? sel.avis : {};

    const format = formatDe(body.format);
    // Le mode suit le format quand il y en a un ; sinon, le choix explicite du client
    const modeChoisi = format ? FORMATS[format].mode
      : (['telephone', 'visio'].includes(body.mode) ? body.mode : null);

    // Réservation d'un créneau : atomique côté base (le premier arrivé l'emporte)
    if (body.action === 'reserver') {
      const id = String(body.creneau_id || '');
      if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ ok: false, error: 'creneau_invalide' }, 400);
      const creneau = await reserverCreneau({
        id, format,
        contact: sel.contact_id || null,
        token,
        nom: sel.client_nom || '',
        message: typeof body.message === 'string' ? body.message.slice(0, 500) : ''
      });
      if (!creneau) {
        return json({ ok: false, error: 'creneau_indisponible', creneaux: await creneauxDisponibles(sel.vendeur || '') }, 409);
      }
      if (modeChoisi && modeChoisi !== creneau.mode) {
        await supabase.from('creneaux').update({ mode: modeChoisi }).eq('id', creneau.id);
        creneau.mode = modeChoisi;
      }
      await calerRappelSurLeRdv(sel.contact_id || null, creneau.debut);
      const cur = (avis['rdv'] && typeof avis['rdv'] === 'object') ? avis['rdv'] : {};
      cur.demande = true;
      cur.reserve = true;
      cur.refuse = false;
      cur.confirme = false;
      cur.propositions = null;
      cur.creneau_id = creneau.id;
      cur.debut = creneau.debut;
      cur.fin = creneau.fin;
      cur.mode = creneau.mode;
      cur.format = format;
      cur.duree = dureeMin(creneau);
      if (creneau.lieu) cur.lieu = creneau.lieu;
      if (typeof body.bien === 'string' && body.bien.trim()) cur.bien = body.bien.slice(0, 200);
      if (typeof body.message === 'string' && body.message.trim()) cur.creneau = body.message.slice(0, 300);
      cur.date = new Date().toISOString();
      avis['rdv'] = cur;
      await supabase.from('selections').update({ avis }).eq('token', token);
      return json({ ok: true, creneau });
    }

    // Le client retient un des créneaux proposés par le conseiller
    if (body.action === 'accepter_proposition') {
      const id = String(body.creneau_id || '');
      if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ ok: false, error: 'creneau_invalide' }, 400);
      const { data: pris, error: errProp } = await supabase.rpc('accepter_proposition', { p_id: id, p_token: token });
      const creneau = Array.isArray(pris) ? pris[0] : pris;
      if (errProp || !creneau || !creneau.id) {
        return json({ ok: false, error: 'creneau_indisponible', propositions: await creneauxProposes(token) }, 409);
      }
      const maj: Record<string, unknown> = {
        contact_id: sel.contact_id || null,
        client_nom: sel.client_nom || null,
        client_message: typeof body.message === 'string' ? body.message.slice(0, 500) : null
      };
      if (modeChoisi) { maj.mode = modeChoisi; creneau.mode = modeChoisi; }
      await supabase.from('creneaux').update(maj).eq('id', creneau.id);
      await calerRappelSurLeRdv(sel.contact_id || null, creneau.debut);

      const cur = (avis['rdv'] && typeof avis['rdv'] === 'object') ? avis['rdv'] : {};
      cur.demande = true;
      cur.reserve = true;
      cur.confirme = true;
      cur.refuse = false;
      cur.propositions = null;
      cur.creneau_id = creneau.id;
      cur.debut = creneau.debut;
      cur.fin = creneau.fin;
      cur.mode = creneau.mode;
      if (format) cur.format = format;
      cur.duree = dureeMin(creneau);
      if (creneau.lieu) cur.lieu = creneau.lieu;
      cur.date = new Date().toISOString();
      avis['rdv'] = cur;
      await supabase.from('selections').update({ avis }).eq('token', token);
      return json({ ok: true, creneau });
    }

    // Demande de rendez-vous libre (aucun créneau proposé ou aucun ne convient)
    if (body.action === 'rdv') {
      const cur = (avis['rdv'] && typeof avis['rdv'] === 'object') ? avis['rdv'] : {};
      cur.demande = true;
      if (typeof body.creneau === 'string' && body.creneau.trim()) cur.creneau = body.creneau.slice(0, 300);
      if (typeof body.bien === 'string' && body.bien.trim()) cur.bien = body.bien.slice(0, 200);
      if (modeChoisi) cur.mode = modeChoisi;
      if (format) cur.format = format;
      cur.date = new Date().toISOString();
      avis['rdv'] = cur;
      await supabase.from('selections').update({ avis }).eq('token', token);
      return json({ ok: true });
    }

    // Le lot n'a pas d'adresse confirmée : le client la demande au conseiller
    if (body.action === 'adresse' && Number.isInteger(body.index) && body.index >= 0 && body.index < 50) {
      const k = String(body.index);
      const cur = avis[k] || {};
      cur.adresse_demandee = true;
      cur.adresse_date = new Date().toISOString();
      cur.date = new Date().toISOString();
      avis[k] = cur;
      await supabase.from('selections').update({ avis }).eq('token', token);
      return json({ ok: true });
    }

    if (body.action === 'avis' && Number.isInteger(body.index) && body.index >= 0 && body.index < 50) {
      const k = String(body.index);
      const cur = avis[k] || {};
      if (['interesse', 'a_discuter', 'pas_pour_moi'].includes(body.choix)) { cur.choix = body.choix; cur.choix_date = new Date().toISOString(); }
      if (typeof body.commentaire === 'string') {
        const texteCom = body.commentaire.slice(0, 1000);
        if (Array.isArray(cur.fil)) {
          // Fil de discussion ouvert par la réponse du conseiller (06/10/2026) :
          // chaque nouveau message du client s'ajoute au fil, rien ne s'efface.
          if (texteCom.trim()) {
            cur.fil = cur.fil.slice(-40).concat([{ de: 'client', texte: texteCom, le: new Date().toISOString() }]);
            cur.commentaire = texteCom; cur.commentaire_date = new Date().toISOString();
          }
        } else {
          cur.commentaire = texteCom; cur.commentaire_date = new Date().toISOString();
        }
      }
      if (body.infos === true) { cur.infos = true; cur.infos_date = new Date().toISOString(); }
      // Demande d'option sur le lot (case à cocher, 09/09/2026) : true / false, le client peut se raviser
      if (typeof body.option === 'boolean') { cur.option = body.option; cur.option_date = new Date().toISOString(); }
      cur.date = new Date().toISOString();
      avis[k] = cur;
      await supabase.from('selections').update({ avis }).eq('token', token);
      return json({ ok: true });
    }

    // Simulation de financement enregistrée par le CLIENT lui-même, en autonomie,
    // depuis sa feuille sélection (22/09/2026, demande d'Alex). Écrit dans
    // contacts.simulations — jamais dans selections — pour vivre sur la fiche
    // du client au même titre qu'une simulation lancée par le vendeur.
    // Historique conservé (20 dernières), la plus récente en tête.
    if (body.action === 'simulation') {
      if (!sel.contact_id) return json({ ok: false, error: 'sans_contact' }, 400);

      const p = (body.profil && typeof body.profil === 'object') ? body.profil : {};
      const profil = {
        projet: typeof p.projet === 'string' ? p.projet.slice(0, 60) : '',
        revenus: Number.isFinite(Number(p.revenus)) ? Math.round(Number(p.revenus)) : null,
        apport: Number.isFinite(Number(p.apport)) ? Math.round(Number(p.apport)) : null,
        duree: Number.isFinite(Number(p.duree)) ? Math.round(Number(p.duree)) : null
      };
      const budgetMax = Number.isFinite(Number(body.budgetMax)) ? Math.round(Number(body.budgetMax)) : null;
      const lots = (Array.isArray(body.lots) ? body.lots : []).slice(0, 30).map((l: any) => ({
        cle: typeof l?.cle === 'string' ? l.cle.slice(0, 200) : '',
        titre: typeof l?.titre === 'string' ? l.titre.slice(0, 200) : '',
        prix: Number.isFinite(Number(l?.prix)) ? Math.round(Number(l.prix)) : null,
        mensualite: Number.isFinite(Number(l?.mensualite)) ? Math.round(Number(l.mensualite)) : null,
        // Économie mensuelle permise par les aides + la TVA réduite sur ce lot
        // (23/09/2026 — affichée sur la feuille sélection, à côté de la mensualité)
        economie: Number.isFinite(Number(l?.economie)) ? Math.round(Number(l.economie)) : null,
        aides: Array.isArray(l?.aides) ? l.aides.filter((a: unknown) => typeof a === 'string').slice(0, 10) : [],
        gains: gainsSur(l?.gains),
        eligible: typeof l?.eligible === 'boolean' ? l.eligible : null
      })).filter((l: any) => l.cle);

      const nouvelle = {
        id: crypto.randomUUID(),
        date: new Date().toISOString(),
        origine: 'client',
        profil,
        budgetMax,
        montage: montageSur(body.montage),
        objectif: objectifSur(body.objectif),
        loyerActuel: loyerSur(body.loyerActuel),
        etat: etatSur(body.etat),
        lots
      };

      const { data: c } = await supabase.from('contacts').select('simulations').eq('id', sel.contact_id).maybeSingle();
      const actuelles: any[] = Array.isArray(c && c.simulations) ? c.simulations : [];
      const simulations = [nouvelle, ...actuelles].slice(0, 20);
      await supabase.from('contacts').update({ simulations }).eq('id', sel.contact_id);
      return json({ ok: true });
    }

    return json({ ok: false }, 400);
  }

  const apercu = url.searchParams.get('apercu') === '1';

  if (url.searchParams.get('data') === '1') {
    // Date de la visite précédente, capturée AVANT de l'écraser : c'est elle qui
    // dit quels lots ont été ajoutés depuis le dernier passage du client.
    const vuAvant = sel.dernier_vu ? new Date(sel.dernier_vu).getTime() : 0;

    if (!apercu) {
      const maj: Record<string, unknown> = { dernier_vu: new Date().toISOString(), visites: (Number(sel.visites) || 0) + 1 };
      if (!sel.opened_at) { maj.opened_at = new Date().toISOString(); sel.opened_at = maj.opened_at as string; }
      await supabase.from('selections').update(maj).eq('token', token);
    }
    if (estExpiree(sel)) {
      return json({ ok: true, expired: true, prenom: prenomDe(sel.client_nom), salutation: salutationDe(sel), vendeur: sel.vendeur || '' });
    }
    const sansTvaReduite = await tvaReduiteExclue(sel.contact_id || null);
    const docsCarte = await documentsCarte(Array.isArray(sel.biens) ? sel.biens : []);
    const biens = await Promise.all(filtrerRegimes(Array.isArray(sel.biens) ? sel.biens : [], sansTvaReduite)
      .map(async (b: any) => {
        const copie: any = completerDocsCarte({ ...b }, docsCarte);
        // Lot ajouté depuis la dernière visite : pastille « Nouveau » côté client.
        // Rien n'est « nouveau » tant que le client n'a jamais ouvert sa sélection.
        const t = (b && b.ajoute_le) ? new Date(b.ajoute_le).getTime() : 0;
        if (t && vuAvant && t > vuAvant) copie.nouveau = true;
        // Adresse non confirmée par le conseiller : elle ne quitte pas le serveur,
        // même pas dans les données brutes de la page.
        if (!copie.adresseOk) {
          delete copie.adresse;
          delete copie.adresseBrute;
          delete copie.geo;
          delete copie.transports;
        } else if (copie.geo && copie.geo.lat != null && copie.geo.lon != null && !(Array.isArray(copie.transports) && copie.transports.length)) {
          // Lot saisi à la main dans le dashboard (adresse choisie dans la liste, jamais passé
          // par extraireOtaree/extraireInterne qui calculent les lignes à proximité) : calculées
          // ici à l'ouverture, y compris pour les sélections déjà envoyées (06/10/2026, bug
          // remonté par Alex — les stations de métro n'apparaissaient pas pour ces lots).
          copie.transports = await transportsProches(copie.geo.lat, copie.geo.lon);
        }
        return copie;
      }));
    return json({
      ok: true,
      expired: false,
      prenom: prenomDe(sel.client_nom),
      salutation: salutationDe(sel),
      vendeur: sel.vendeur || '',
      message: sel.message || '',
      biens,
      avis: (sel.avis && typeof sel.avis === 'object') ? sel.avis : {},
      formats: FORMATS,
      creneaux: apercu ? [] : await creneauxDisponibles(sel.vendeur || ''),
      propositions: apercu ? [] : await creneauxProposes(token),
      // Dernier résumé de simulation de financement (nul si aucune simulation encore faite)
      simulation: await derniereSimulation(sel.contact_id || null),
      created_at: sel.created_at,
      expires_at: sel.expires_at,
      maj_at: sel.maj_at || null
    });
  }

  if (!apercu && !sel.opened_at) {
    await supabase.from('selections').update({ opened_at: new Date().toISOString() }).eq('token', token);
  }
  return Response.redirect((await pageUrl()) + '?t=' + encodeURIComponent(token) + (apercu ? '&apercu=1' : ''), 302);
});
