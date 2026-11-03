import { createClient } from 'npm:@supabase/supabase-js@2';

// Page publique de prise de rendez-vous, hébergée sur GitHub Pages
// Depuis le 02/09/2026 la page vit sur le site de la maison (dépôt glr-site,
// rdv/index.html). Tant que ce dossier n'est pas en ligne, on retombe sur
// l'ancienne adresse GitHub Pages : aucun lien déjà envoyé ne doit casser.
const PAGE_URL = 'https://www.glrimmobilier.com/rdv/';
const PAGE_URL_SECOURS = 'https://alexandregrillault.github.io/glrimmobilier/rdv.html';
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

// Fenêtre de proposition des créneaux au client
const RDV_JOURS_VISIBLES = 21;

// Deux formats de rendez-vous (choix d'Alex, 2 septembre 2026) :
//   · visio : 30 min, on prend le temps de montrer — le bien, le programme,
//             le process, le financement, d'autres lots ;
//   · appel : 10 min par téléphone, une première esquisse du projet.
// (Durées ramenées de 45/15 à 30/10 le 02/09/2026 : des créneaux plus courts
// font moins peur au client.) Le client ne bloque que la durée réelle : la
// réservation passe par reserver_duree(), qui enchaîne les créneaux de 10 min
// contigus si besoin et rend le temps restant proposable à d'autres.
const FORMATS: Record<string, { duree: number; mode: string }> = {
  visio: { duree: 30, mode: 'visio' },
  appel: { duree: 10, mode: 'telephone' }
};
const formatDe = (v: unknown): string | null => (typeof v === 'string' && FORMATS[v]) ? v : null;

// Deux sortes de liens :
//   · personnel  : rattaché à un client connu (fiche, ou demande portail) ;
//   · public     : le lien fixe d'un commercial, partageable à quelqu'un qui
//                 n'est pas encore en base. Il choisit son créneau, se présente,
//                 et sa fiche est créée à ce moment-là avec un lien personnel.

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

// Un navigateur qui suit ce lien part TOUJOURS sur la page, même quand le jeton
// ne vaut plus rien : c'est elle qui dira « ce lien n'est plus valable », avec le
// logo et les couleurs de la maison. Rien d'autre ne doit s'afficher depuis le
// domaine supabase.co : sa passerelle réécrit toute réponse d'erreur en
// text/plain + nosniff, et un mobile la télécharge alors comme un fichier au nom
// illisible — le client croit à une tentative de piratage.
// Le format choisi depuis le mail (?f=visio|appel) suit jusqu'à la page.
const versLaPage = async (t: string, f: string | null) =>
  Response.redirect((await pageUrl()) + '?t=' + encodeURIComponent(t || '') + (f ? '&f=' + f : ''), 302);

const estExpire = (l: any) => !!(l.expires_at && new Date(l.expires_at).getTime() < Date.now());

const prenomDe = (nom: string) => {
  const p = String(nom || '').trim().split(/\s+/)[0] || '';
  return p && p === p.toLowerCase() ? p.charAt(0).toUpperCase() + p.slice(1) : p;
};

const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;

// Caractères écrits par leur code : le déploiement décode les séquences \uXXXX
// et les caractères invisibles tapés en clair ne survivent pas toujours.
const RE_CONTROLES = new RegExp('[' + String.fromCharCode(0) + '-' + String.fromCharCode(31) + ']', 'g');
const RE_DIACRITIQUES = new RegExp('[' + String.fromCharCode(0x300) + '-' + String.fromCharCode(0x36f) + ']', 'g');

function texte(v: unknown, max: number): string {
  return String(v ?? '').replace(RE_CONTROLES, ' ').trim().slice(0, max);
}

function normPhone(p: string): string | null {
  let d = String(p || '').replace(/\D/g, '');
  if (d.startsWith('33')) d = '0' + d.slice(2);
  return d.length >= 9 ? d : null;
}

function formatPhone(p: string): string {
  const n = normPhone(p);
  if (!n || n.length !== 10) return String(p || '').trim();
  return '+33 ' + n.slice(1).replace(/(\d)(\d{2})(\d{2})(\d{2})(\d{2})/, '$1 $2 $3 $4 $5');
}

// Découpage prénom / nom, même logique que pour les leads des portails
function decouperNom(nom: string): { prenom: string | null; nom_famille: string | null } {
  const mots = String(nom || '').trim().split(/\s+/).filter(Boolean);
  if (!mots.length) return { prenom: null, nom_famille: null };
  if (mots.length === 1) return { prenom: mots[0], nom_famille: null };
  const majs = mots.filter((m) => m.length > 1 && m === m.toUpperCase() && m !== m.toLowerCase());
  if (majs.length && majs.length < mots.length) {
    return {
      prenom: mots.filter((m) => !majs.includes(m)).join(' ') || null,
      nom_famille: majs.join(' ') || null
    };
  }
  return { prenom: mots.slice(0, -1).join(' ') || null, nom_famille: mots[mots.length - 1] || null };
}

function jeton(): string {
  const o = new Uint8Array(12);
  crypto.getRandomValues(o);
  return Array.from(o).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// « Théophile » → « theophile » : le prénom tel qu'il s'écrit dans une adresse
const slugDe = (s: unknown) => String(s || '').normalize('NFD').replace(RE_DIACRITIQUES, '').toLowerCase().replace(/[^a-z0-9]/g, '');

// Une adresse de visio propre, ou vide
const visioPropre = (v: unknown) => { const u = String(v || '').trim(); return /^https?:\/\/\S+$/.test(u) ? u : ''; };

// Salle de visio fixe du conseiller (fiche vendeur, champ « Lien de visio »),
// pour le bloc « Entrer dans la visio » de la page du rendez-vous (11/09/2026).
async function salleDuVendeur(vendeur: string): Promise<string> {
  if (!vendeur) return '';
  try {
    const cible = slugDe(vendeur);
    const { data: dash } = await supabase.from('dashboard_data').select('vendeurs').eq('id', 'main').maybeSingle();
    const vendeurs: any[] = Array.isArray(dash?.vendeurs) ? dash!.vendeurs : [];
    const v = vendeurs.find((x: any) => slugDe(x && x.prenom) === cible);
    return visioPropre(v && v.visio);
  } catch (_) { return ''; }
}

// Jeton du lien public d'un commercial, à partir de son prénom en adresse.
// Créé à la volée s'il n'existe pas encore, pour peu que le prénom soit celui
// d'un vendeur du dashboard (table dashboard_data, liste vendeurs).
async function tokenPublicDuVendeur(slug: string): Promise<string> {
  if (!slug) return '';
  const { data: pubs } = await supabase.from('rdv_liens').select('token, vendeur').eq('origine', 'public');
  const deja = (pubs || []).find((x: any) => slugDe(x.vendeur) === slug);
  if (deja) return deja.token as string;
  const { data: dash } = await supabase.from('dashboard_data').select('vendeurs').eq('id', 'main').maybeSingle();
  const vendeurs: any[] = Array.isArray(dash?.vendeurs) ? dash!.vendeurs : [];
  const v = vendeurs.find((x: any) => slugDe(x && x.prenom) === slug);
  if (!v || !v.prenom) return '';
  const t = jeton();
  const { error } = await supabase.from('rdv_liens').insert({ token: t, contact_id: null, vendeur: v.prenom, origine: 'public' });
  if (error) {
    // Créé entre-temps depuis le dashboard : on le relit
    const { data: re } = await supabase.from('rdv_liens').select('token, vendeur').eq('origine', 'public');
    const p = (re || []).find((x: any) => slugDe(x.vendeur) === slug);
    return p ? (p.token as string) : '';
  }
  return t;
}

// Garde-fou anti-robot sur le lien public : 5 envois par IP et par tranche de 10 min
const FENETRE_MS = 10 * 60 * 1000;
const MAX_PAR_FENETRE = 5;
const historique = new Map<string, number[]>();
function tropDeEnvois(ip: string): boolean {
  const now = Date.now();
  const passages = (historique.get(ip) || []).filter((t) => now - t < FENETRE_MS);
  passages.push(now);
  historique.set(ip, passages);
  if (historique.size > 5000) historique.clear();
  return passages.length > MAX_PAR_FENETRE;
}

// Créneaux encore libres du conseiller, dans la fenêtre visible. Chaque créneau
// porte `duree_max` : le temps libre d'affilée à partir de son début (créneaux
// contigus enchaînés), pour que la page ne propose la visio de 30 min que là
// où elle tient vraiment.
// Depuis le 02/09/2026 les disponibilités sont des créneaux de 10 min :
// jusqu'à 2 500 sur trois semaines, d'où la limite large.
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
// que la durée réelle via reserver_duree ; sans format (ancienne page), on
// prend le créneau tel quel.
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

const dureeMin = (c: any) => Math.round((new Date(c.fin).getTime() - new Date(c.debut).getTime()) / 60000);

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

// Le contact fait foi pour le vendeur : un client transféré atterrit chez son
// nouveau conseiller sans avoir à renvoyer de lien.
async function contactDuLien(lien: any) {
  if (!lien.contact_id) return null;
  const { data } = await supabase.from('contacts')
    .select('id, nom, prenom, nom_famille, vendeur, lieu, typologie, prix_annonce, reference_annonce, source, date_lead')
    .eq('id', lien.contact_id).maybeSingle();
  return data || null;
}

// Quelqu'un se présente depuis le lien public : on retrouve sa fiche ou on la crée.
// Règle du 10/09/2026 (remplace celle du 01/09) : le lien public ne prend pas un
// client à un collègue qui le travaille. La porte unique de paternité en base
// décide : client libre ou paternité échue → à celui qui a donné le lien ;
// compétition ouverte ou client en veille → le rendez-vous vaut première action,
// il est à lui ; client suivi → la demande est notée chez son vendeur, avec un
// rappel du jour, et aucun créneau n'est pris sur le lien.
async function ficheDuVisiteur(v: { nom: string; email: string; telephone: string; projet: string; vendeur: string }): Promise<{ id: string; suiviPar: string | null } | null> {
  const nowIso = new Date().toISOString();
  const today = nowIso.slice(0, 10);
  const tel = formatPhone(v.telephone);
  const telNorm = normPhone(v.telephone);
  const { prenom, nom_famille } = decouperNom(v.nom);

  const champs = 'id, nom, prenom, nom_famille, nom_confirme, notes, email, telephone, vendeur, vendeur_depuis, vendeur_historique, recu_par, paternite_geree, rappel_le';
  let existing: any = null;
  if (v.email) {
    const { data } = await supabase.from('contacts').select(champs).ilike('email', v.email).limit(1);
    if (data?.length) existing = data[0];
  }
  if (!existing && telNorm) {
    const { data } = await supabase.from('contacts').select(champs).eq('telephone_norm', telNorm).limit(1);
    if (data?.length) existing = data[0];
  }

  const note = `[${today}] A pris rendez-vous depuis le lien de ${v.vendeur}` +
    (v.projet ? ` — « ${v.projet} »` : '');

  if (existing) {
    const upd: Record<string, unknown> = { recu_le: nowIso };
    if (v.email && !existing.email) upd.email = v.email;
    if (tel && !existing.telephone) upd.telephone = tel;
    if (!existing.nom_confirme) {
      if (!existing.prenom && prenom) upd.prenom = prenom;
      if (!existing.nom_famille && nom_famille) upd.nom_famille = nom_famille;
      if (!existing.nom && v.nom) upd.nom = v.nom;
    }
    await supabase.from('contacts').update(upd).eq('id', existing.id);

    let statut = 'erreur';
    try {
      const { data, error } = await supabase.rpc('paternite_recevoir', { p_contact: existing.id, p_vendeur: v.vendeur, p_source: 'Lien rendez-vous' });
      if (!error && data && data.statut) statut = String(data.statut);
    } catch (_) { statut = 'erreur'; }

    if (statut === 'conservee' || statut === 'erreur' || statut === 'sans_vendeur') {
      // Client suivi par un collègue : il reste chez lui, qui est prévenu et le rappelle
      const { data: c } = await supabase.from('contacts').select('notes, rappel_le, vendeur').eq('id', existing.id).maybeSingle();
      const proprio = (c && c.vendeur) || existing.vendeur || null;
      const noteS = `[${today}] A demandé un rendez-vous depuis le lien de ${v.vendeur}` + (v.projet ? ` — « ${v.projet} »` : '') +
        (proprio ? ` — client suivi par ${proprio}, qui le rappelle` : '');
      const majS: Record<string, unknown> = { notes: (c && c.notes) ? c.notes + '\n' + noteS : noteS };
      if (!(c && c.rappel_le) || String(c.rappel_le) > today) {
        majS.rappel_le = today;
        majS.rappel_titre = `Rappeler — a demandé un RDV via le lien de ${v.vendeur}`;
      }
      await supabase.from('contacts').update(majS).eq('id', existing.id);
      return { id: existing.id as string, suiviPar: proprio };
    }

    // Libre, échu, en compétition ou en veille : le rendez-vous vaut première action
    // pour celui dont le lien a été suivi, ses 14 jours démarrent
    const { data: c2 } = await supabase.from('contacts').select('vendeur, vendeur_depuis, vendeur_historique, notes').eq('id', existing.id).maybeSingle();
    const maj: Record<string, unknown> = {
      premiere_action_le: nowIso,
      derniere_action_le: nowIso,
      paternite_jusqu_au: new Date(Date.now() + 14 * 86400000).toISOString()
    };
    let mention = '';
    if (c2 && c2.vendeur !== v.vendeur) {
      const hist = Array.isArray(c2.vendeur_historique) ? c2.vendeur_historique.slice() : [];
      if (c2.vendeur) hist.push({ vendeur: c2.vendeur, du: c2.vendeur_depuis || null, au: nowIso, motif: `rendez-vous pris depuis le lien de ${v.vendeur}` });
      maj.vendeur_historique = hist;
      maj.vendeur = v.vendeur;
      maj.vendeur_depuis = nowIso;
      maj.paternite_geree = true;
      mention = c2.vendeur ? ` — PATERNITÉ TRANSFÉRÉE de ${c2.vendeur} à ${v.vendeur}` : ` — paternité attribuée à ${v.vendeur}`;
    }
    maj.notes = (c2 && c2.notes) ? c2.notes + '\n' + note + mention : note + mention;
    await supabase.from('contacts').update(maj).eq('id', existing.id);
    return { id: existing.id as string, suiviPar: null };
  }

  const { data: cree, error } = await supabase.from('contacts').insert({
    nom: v.nom, prenom, nom_famille,
    email: v.email || null,
    telephone: tel || null,
    message: v.projet || null,
    statut: 'Nouveau',
    source: 'Lien rendez-vous',
    vendeur: v.vendeur,
    date_lead: today,
    recu_le: nowIso,
    vendeur_depuis: nowIso,
    recu_par: [{ vendeur: v.vendeur, le: nowIso }],
    paternite_geree: true,
    premiere_action_le: nowIso,
    derniere_action_le: nowIso,
    paternite_jusqu_au: new Date(Date.now() + 14 * 86400000).toISOString(),
    notes: note
  }).select('id').single();

  if (error || !cree) return null;
  return { id: cree.id as string, suiviPar: null };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const url = new URL(req.url);

  let body: any = null;
  if (req.method === 'POST') {
    try { body = await req.json(); } catch (_) { body = {}; }
  }

  const parts = url.pathname.split('/').filter(Boolean);
  const last = parts[parts.length - 1] || '';
  let token = url.searchParams.get('t') || (last !== 'rdv' ? last : '');
  const donnees = url.searchParams.get('data') === '1';
  const fUrl = formatDe(url.searchParams.get('f'));

  // Adresse par prénom (glrimmobilier.com/rdv/?v=nour) : ?v=nour désigne le lien
  // public du commercial, sans jeton dans l'adresse. Le lien est créé au
  // premier passage si le prénom est bien celui d'un vendeur du dashboard.
  const vSlug = slugDe(url.searchParams.get('v') || '');
  if (!token && vSlug) {
    token = await tokenPublicDuVendeur(vSlug);
    if (!token) return json({ ok: false, error: 'vendeur_inconnu' }, 404);
  }

  if (!token || !/^[a-f0-9]{6,32}$/i.test(token)) {
    if (req.method === 'POST' || donnees) return json({ ok: false, error: 'lien_invalide' }, 404);
    return versLaPage(token, fUrl);
  }

  const { data: lien, error } = await supabase.from('rdv_liens')
    .select('token, contact_id, vendeur, origine, contexte, rdv, created_at, expires_at, opened_at, visites')
    .eq('token', token).maybeSingle();

  if (error || !lien) {
    if (req.method === 'POST' || donnees) return json({ ok: false, error: 'lien_invalide' }, 404);
    return versLaPage(token, fUrl);
  }

  const estPublic = lien.origine === 'public';
  const contact = await contactDuLien(lien);
  const vendeur = (contact && contact.vendeur) || lien.vendeur || '';
  const rdv: any = (lien.rdv && typeof lien.rdv === 'object') ? lien.rdv : {};

  // ---------------- Actions du client ----------------
  if (req.method === 'POST') {
    if (body.action === 'ouvert') {
      const maj: Record<string, unknown> = { dernier_vu: new Date().toISOString(), visites: (Number(lien.visites) || 0) + 1 };
      if (!lien.opened_at) maj.opened_at = new Date().toISOString();
      await supabase.from('rdv_liens').update(maj).eq('token', token);
      return json({ ok: true });
    }

    if (estExpire(lien)) return json({ ok: false, error: 'expire' }, 410);

    const format = formatDe(body.format);
    // Le mode suit le format quand il y en a un ; sinon, le choix explicite du client
    const modeDemande = format ? FORMATS[format].mode
      : (['telephone', 'visio'].includes(body.mode) ? body.mode : null);

    // --- Lien public : le visiteur se présente en même temps qu'il réserve
    if (body.action === 'reserver_public') {
      if (!estPublic) return json({ ok: false, error: 'lien_non_public' }, 400);

      // Piège à robots : champ invisible pour un humain
      if (texte(body.societe, 200)) return json({ ok: true, token });

      const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'inconnue';
      if (tropDeEnvois(ip)) return json({ ok: false, error: 'trop_de_demandes' }, 429);

      const nom = texte(body.nom, 80);
      const email = texte(body.email, 160).toLowerCase();
      const telephone = texte(body.telephone, 40);
      const projet = texte(body.projet, 500);

      if (nom.length < 2) return json({ ok: false, error: 'nom_manquant' }, 422);
      if (!RE_EMAIL.test(email)) return json({ ok: false, error: 'email_invalide' }, 422);
      if (!normPhone(telephone)) return json({ ok: false, error: 'telephone_invalide' }, 422);

      const fiche = await ficheDuVisiteur({ nom, email, telephone, projet, vendeur });
      if (!fiche) return json({ ok: false, error: 'fiche_impossible' }, 500);
      if (fiche.suiviPar) {
        // Client déjà suivi par un collègue : aucun créneau pris ici, son conseiller
        // a un rappel du jour et le recontacte. La page affiche « demande transmise ».
        return json({ ok: true, token, demande: true, suivi: true });
      }
      const contactId = fiche.id;

      // Chacun repart avec son propre lien : l'état de SON rendez-vous y vit,
      // et le lien public reste utilisable par les suivants.
      const perso = jeton();
      const { error: errLien } = await supabase.from('rdv_liens').insert({
        token: perso, contact_id: contactId, vendeur, origine: 'public_pris',
        contexte: { projet, depuis: 'lien public de ' + vendeur, nom }
      });
      if (errLien) return json({ ok: false, error: 'lien_impossible' }, 500);

      const mode = modeDemande || 'telephone';
      const idCreneau = String(body.creneau_id || '');

      // Sans créneau choisi (le vendeur n'en a pas ouvert) : simple demande de rappel
      if (!idCreneau) {
        await supabase.from('rdv_liens').update({
          rdv: { demande: true, traite: false, mode, format, creneau: texte(body.creneau, 300) || null, date: new Date().toISOString() }
        }).eq('token', perso);
        return json({ ok: true, token: perso, demande: true });
      }

      if (!/^[0-9a-f-]{36}$/i.test(idCreneau)) return json({ ok: false, error: 'creneau_invalide' }, 400);
      const creneau = await reserverCreneau({ id: idCreneau, format, contact: contactId, token: perso, nom, message: projet.slice(0, 500) });
      if (!creneau) {
        return json({ ok: false, error: 'creneau_indisponible', token: perso, creneaux: await creneauxDisponibles(vendeur) }, 409);
      }
      if (mode !== creneau.mode) {
        await supabase.from('creneaux').update({ mode }).eq('id', creneau.id);
        creneau.mode = mode;
      }
      await calerRappelSurLeRdv(contactId, creneau.debut);
      await supabase.from('rdv_liens').update({
        rdv: {
          demande: true, reserve: true, confirme: false, refuse: false,
          creneau_id: creneau.id, debut: creneau.debut, fin: creneau.fin, mode: creneau.mode,
          format, duree: dureeMin(creneau),
          date: new Date().toISOString()
        }
      }).eq('token', perso);

      return json({ ok: true, token: perso, creneau });
    }

    if (estPublic) return json({ ok: false, error: 'presentation_requise' }, 400);

    const nomClient = (contact && (contact.nom || [contact.prenom, contact.nom_famille].filter(Boolean).join(' '))) || '';

    // Réservation d'un créneau : atomique côté base (le premier arrivé l'emporte)
    if (body.action === 'reserver') {
      const id = String(body.creneau_id || '');
      if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ ok: false, error: 'creneau_invalide' }, 400);
      const creneau = await reserverCreneau({
        id, format,
        contact: lien.contact_id || null,
        token,
        nom: nomClient,
        message: typeof body.message === 'string' ? body.message.slice(0, 500) : ''
      });
      if (!creneau) {
        return json({ ok: false, error: 'creneau_indisponible', creneaux: await creneauxDisponibles(vendeur) }, 409);
      }
      if (modeDemande && modeDemande !== creneau.mode) {
        await supabase.from('creneaux').update({ mode: modeDemande }).eq('id', creneau.id);
        creneau.mode = modeDemande;
      }
      await calerRappelSurLeRdv(lien.contact_id || null, creneau.debut);
      const cur = { ...rdv };
      cur.demande = true; cur.reserve = true; cur.refuse = false; cur.confirme = false;
      cur.propositions = null;
      cur.creneau_id = creneau.id;
      cur.debut = creneau.debut; cur.fin = creneau.fin; cur.mode = creneau.mode;
      cur.format = format; cur.duree = dureeMin(creneau);
      if (creneau.lieu) cur.lieu = creneau.lieu;
      if (typeof body.message === 'string' && body.message.trim()) cur.creneau = body.message.slice(0, 300);
      cur.date = new Date().toISOString();
      await supabase.from('rdv_liens').update({ rdv: cur }).eq('token', token);
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
        contact_id: lien.contact_id || null,
        client_nom: nomClient || null,
        client_message: typeof body.message === 'string' ? body.message.slice(0, 500) : null
      };
      if (modeDemande) { maj.mode = modeDemande; creneau.mode = modeDemande; }
      await supabase.from('creneaux').update(maj).eq('id', creneau.id);
      await calerRappelSurLeRdv(lien.contact_id || null, creneau.debut);

      const cur = { ...rdv };
      cur.demande = true; cur.reserve = true; cur.confirme = true; cur.refuse = false;
      cur.propositions = null;
      cur.creneau_id = creneau.id;
      cur.debut = creneau.debut; cur.fin = creneau.fin; cur.mode = creneau.mode;
      if (format) cur.format = format;
      cur.duree = dureeMin(creneau);
      if (creneau.lieu) cur.lieu = creneau.lieu;
      cur.date = new Date().toISOString();
      await supabase.from('rdv_liens').update({ rdv: cur }).eq('token', token);
      return json({ ok: true, creneau });
    }

    // Demande libre : aucun créneau ne convient (ou le vendeur n'en a pas ouvert)
    if (body.action === 'rdv') {
      const cur = { ...rdv };
      cur.demande = true;
      cur.traite = false;
      if (typeof body.creneau === 'string' && body.creneau.trim()) cur.creneau = body.creneau.slice(0, 300);
      if (modeDemande) cur.mode = modeDemande;
      if (format) cur.format = format;
      cur.date = new Date().toISOString();
      await supabase.from('rdv_liens').update({ rdv: cur }).eq('token', token);
      return json({ ok: true });
    }

    return json({ ok: false }, 400);
  }

  // ---------------- Données de la page ----------------
  if (donnees) {
    const maj: Record<string, unknown> = { dernier_vu: new Date().toISOString(), visites: (Number(lien.visites) || 0) + 1 };
    if (!lien.opened_at) maj.opened_at = new Date().toISOString();
    await supabase.from('rdv_liens').update(maj).eq('token', token);

    // Lien né du planning public (03/11/2026) : rien ne prouve que le visiteur est le
    // propriétaire de l'e-mail ou du téléphone qu'il a tapés, qui ont pu le rattacher à
    // la fiche d'un vrai client. La page ne montre que ce qu'il a tapé lui-même, jamais
    // le prénom ni le projet de la fiche.
    const depuisPublic = lien.origine === 'public_pris';
    const ctx: any = (lien.contexte && typeof lien.contexte === 'object') ? lien.contexte : {};
    const fiche: any = depuisPublic ? null : contact;

    if (estExpire(lien)) {
      return json({ ok: true, expired: true, prenom: prenomDe(depuisPublic ? (ctx.nom || '') : (contact && contact.nom || '')), vendeur });
    }

    if (estPublic) {
      return json({
        ok: true,
        expired: false,
        public: true,
        token,          // la page par prénom en a besoin pour ses envois
        vendeur,
        bien: null,
        rdv: {},
        formats: FORMATS,
        creneaux: await creneauxDisponibles(vendeur),
        propositions: [],
        created_at: lien.created_at
      });
    }

    // Le bien sur lequel le client a cliqué, figé au moment de la demande.
    // À défaut (lien créé à la main), on reprend ce que porte la fiche.
    const bien = {
      ville: ctx.ville || (fiche && fiche.lieu) || '',
      typologie: ctx.typologie || (fiche && fiche.typologie) || '',
      programme: ctx.programme || '',
      prix: ctx.prix != null ? ctx.prix : ((fiche && fiche.prix_annonce) || null),
      reference: ctx.reference || '',
      source: ctx.source || (fiche && fiche.source) || '',
      date: ctx.date || (fiche && fiche.date_lead) || ''
    };

    // Salle de visio du rendez-vous : un lien collé sur le créneau prime sur la
    // salle fixe du conseiller (même règle que le mail de confirmation).
    const visio = (rdv.reserve && rdv.mode === 'visio' && !rdv.refuse)
      ? (visioPropre(rdv.lieu) || await salleDuVendeur(vendeur))
      : '';

    return json({
      ok: true,
      expired: false,
      public: false,
      prenom: prenomDe(depuisPublic ? (ctx.nom || '') : ((contact && contact.prenom) || (contact && contact.nom) || '')),
      vendeur,
      bien,
      rdv,
      visio,
      formats: FORMATS,
      creneaux: await creneauxDisponibles(vendeur),
      propositions: await creneauxProposes(token),
      created_at: lien.created_at
    });
  }

  // ---------------- Redirection vers la page ----------------
  if (!lien.opened_at) {
    await supabase.from('rdv_liens').update({ opened_at: new Date().toISOString() }).eq('token', token);
  }
  return versLaPage(token, fUrl);
});
