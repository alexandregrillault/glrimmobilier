// Visites 3D des programmes sur les pages ville du site (www.glrimmobilier.com/neuf/<ville>/<programme>/).
//
// Version 7, en ligne depuis le 27/11/2026 (« Oui, la v7 », puis « déploie et pousse ») : lien de l'immeuble gardé
// 4 minutes, nouvel essai si le stockage refuse un lien (429), 503 « reessayer » au lieu de 404.
// Version 6 en ligne : anciennes/index_v6.ts (une fiche existante qui a un vendeur le garde, « Reste chez le
// vendeur »). Version 5 : anciennes/index_v5.ts.
// Version 5 (27/11/2026, « deploi et pousse » d'Alex) ; dépend de 20261127_plans_2d.sql :
//   - fiche existante au statut « Perdu » : repasse en « Nouveau » (« repasse en statut actif ») ;
//   - plan du promoteur après le formulaire (Alex, 27/11/2026 : « mets le plan du promoteur après le
//     formulaire », puis « ok pour le B » : images converties par le robot, espace privé), sur tous les
//     programmes montrés : GET ?p=&l=&t=&doc=plan&page= ;
//   - inscription refusée (404) pour un programme non montré ; limite du formulaire comptée en base.
// Version 4 en ligne : anciennes/index_v4.ts (plus de champ piège, « delai_ms », 1,5 s minimum).
// v3 : anciennes/index_v3.ts ; v2 : anciennes/index_v2.ts ; v1 : anciennes/index_v1.ts.
// verify_jwt = false (page publique, sans connexion). Dépend des migrations 20261127_plans_3d.sql,
// 20261127_plans_3d_note.sql et 20261127_plans_3d_immeuble_public.sql.
// Version 2 (Alex, 27/11/2026 : « source du lead mets juste site web », « je veux ue le client voit le
// nouvelle immeuble qu'on a mis en place et il pourra voir les plans uniquement si il a un compte ») :
// source « Site web » ; l'immeuble sans jeton, les logements toujours avec.
//
// Décisions d'Alex (27/11/2026) : la 3D se voit « Après le formulaire » ; « oui c'est mieux que appelez
// nous. mets les leads chez moi, et garde les numéros de lots. »
//
// 1. Le formulaire de la fiche programme
//    POST { action: "inscrire", prenom, telephone, email, accord: true, p: <clé programme>,
//           programme?: <nom affiché>, ville?: <ville affichée>, delai_ms?: <ms entre affichage et clic> }
//    → 200 { jeton }   (la page le garde dans le navigateur : 30 jours, pour toutes les visites du site)
//    → 404 programme non montré, 422 champs manquants, 429 trop d'envois, 502 enregistrement impossible.
//    Le lead est créé chez Alexandre ; une fiche existante est rattachée sans changer de vendeur (v6), une
//    fiche existante sans vendeur va chez Alexandre ; directement en base : AUCUN mail ni SMS n'est envoyé au client. On ne passe
//    pas par lead-inbound, qui envoie de lui-même un accusé avec un lien de rendez-vous.
//
// 2. Un fichier de la visite
//    GET ?p=<clé programme>                      → l'immeuble, sans jeton
//    GET ?p=<clé programme>&l=<clé lot>&t=<jeton> → les plans d'un logement, jeton obligatoire
//    GET ?p=<clé programme>&l=<clé lot>&t=<jeton>&doc=plan[&page=n] → le plan du promoteur converti en
//      image : { url, expire: 300, pages } (lien temporaire vers <clé lot>/<n>.webp de l'espace privé
//      plans2d) ; 401 / 404 / 429 comme ci-dessous. Note « Plan 2D : lot … » sur la fiche à la première
//      ouverture. Compteurs communs avec la 3D.
//    → 200 { url, expire: 300 }  lien temporaire (5 minutes) vers la page HTML, à télécharger tout de suite
//      (le stockage sert le HTML en texte brut : la page l'affiche par un lien blob:, pas par iframe src=).
//    → 401 jeton absent, faux ou expiré pour un logement (la page montre le formulaire), 404 inconnu,
//      429 trop de demandes, 503 « reessayer » (stockage momentanément saturé : la page réessaie).
//    Limite contre l'aspiration (en base, neuf_3d_acces) : 40 fichiers par jeton et 60 par adresse, par jour ;
//    l'immeuble public n'est pas compté (migration 20261127_plans_3d_immeuble_hors_limite.sql).
//    À la première ouverture d'un logement, la base ajoute aux notes de la fiche du client une ligne
//    « [JJ/MM/AAAA] Visite 3D : lot A001 (T3, 61 m²), Esprit Valmy à Colombes » (une fois par logement).

import { createClient } from "npm:@supabase/supabase-js@2";

const VENDEUR = "Alexandre";             // « mets les leads chez moi » (Alex, 27/11/2026)
const SOURCE = "Site web";               // « source du lead mets juste site web » (Alex, 27/11/2026)
const DUREE_LIEN = 300;                  // secondes
const DELAI_MIN_MS = 1500;               // anti-robots : temps minimal entre affichage et envoi (accord avec Site)
const ESPACE = "plans3d";
const ESPACE_PLANS = "plans2d";          // plans du promoteur convertis en images (privé)

const ORIGINES_AUTORISEES = [
  "https://www.glrimmobilier.com",
  "https://glrimmobilier.com",
];

// Formulaire : 3 envois par tranche de 10 minutes et par adresse, compté en base (neuf_3d_formulaire,
// v5) : le formulaire est sur toutes les fiches, et un compteur en mémoire se perdait à chaque redémarrage.

function entetesCors(origin: string | null) {
  const autorise = origin && ORIGINES_AUTORISEES.includes(origin) ? origin : ORIGINES_AUTORISEES[0];
  return {
    "Access-Control-Allow-Origin": autorise,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function repondre(corps: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(corps), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function texte(v: unknown, max: number): string {
  return String(v ?? "").replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, "").trim().slice(0, max);
}

const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;
const RE_CLE = /^[0-9a-f]{12}$/;

async function sha256(s: string): Promise<string> {
  const hache = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  return Array.from(hache).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// v7 : le stockage de Supabase refuse parfois de créer un lien temporaire quand les demandes arrivent
// en rafale (429). On réessaie une fois après 300 ms ; si le refus persiste, la page reçoit 503 « réessayer »
// (et non plus 404 « inconnu »). Le lien de l'immeuble, public et identique pour tous, est gardé en mémoire
// 4 minutes (il en vaut 5) : en temps normal, un seul lien par immeuble toutes les 4 minutes.
const CACHE_IMMEUBLE_MS = 4 * 60 * 1000;
const cacheImmeuble = new Map<string, { url: string; jusqua: number }>();

async function lienSigne(supabase: any, espace: string, chemin: string): Promise<string | null> {
  for (let essai = 0; essai < 2; essai++) {
    const { data, error } = await supabase.storage.from(espace).createSignedUrl(chemin, DUREE_LIEN);
    if (!error && data?.signedUrl) return data.signedUrl;
    if (essai === 0) await new Promise((r) => setTimeout(r, 300));
  }
  return null;
}

// Même normalisation que lead-inbound : chiffres seuls, +33 → 0 (et « +33 (0)6… » → 06…).
function normTel(p: string): string | null {
  let d = p.replace(/\D/g, "");
  if (d.startsWith("0033")) d = d.slice(2);
  if (d.startsWith("330")) d = "0" + d.slice(3);
  else if (d.startsWith("33")) d = "0" + d.slice(2);
  return d.length >= 9 ? d : null;
}

function formatTel(p: string): string {
  const n = normTel(p);
  if (!n || n.length !== 10) return p;
  return "+33 " + n.slice(1).replace(/(\d)(\d{2})(\d{2})(\d{2})(\d{2})/, "$1 $2 $3 $4 $5");
}

function adresseIp(req: Request): string {
  return req.headers.get("cf-connecting-ip")?.trim() ||
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "inconnue";
}

const CHAMPS_CONTACT = "id, notes, prenom, nom_confirme, statut, vendeur";

async function inscrire(req: Request, cors: Record<string, string>) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return repondre({ error: "invalid_json" }, 400, cors);
  }
  if (body.action !== "inscrire") return repondre({ error: "action_inconnue" }, 400, cors);

  // Anti-robots v4 (27/11/2026) : plus aucun champ caché. Les deux essais d'Alex ont été pris pour des
  // robots parce que le remplissage automatique de Chrome remplissait le champ piège (« societe » en v2,
  // « hp_glr » en v3) ; ces champs sont désormais ignorés. La page envoie « delai_ms » : le temps en
  // millisecondes entre l'affichage de la page et le clic sur « Créer mon accès ». Un humain met plus
  // de 5 secondes, un remplissage automatique rapide environ 1,6 s : en dessous de 1,5 s, on répond comme
  // si tout allait bien, sans rien enregistrer. Sans « delai_ms » (page encore en cache), on accepte.
  // S'ajoute la limite de 3 envois par 10 minutes et par adresse, plus bas.
  if (body.delai_ms !== undefined && body.delai_ms !== null && body.delai_ms !== "") {
    const delai = Number(body.delai_ms);
    if (!Number.isFinite(delai) || delai < DELAI_MIN_MS) {
      return repondre({ jeton: crypto.randomUUID().replace(/-/g, "") }, 200, cors);
    }
  }

  const prenom = texte(body.prenom, 60);
  const telephone = texte(body.telephone, 40);
  const email = texte(body.email, 160).toLowerCase();
  const cle = texte(body.p, 12).toLowerCase();
  const programme = texte(body.programme, 120);
  const ville = texte(body.ville, 80);
  const telNorm = normTel(telephone);

  if (!prenom || !telNorm || body.accord !== true || !RE_EMAIL.test(email) || !RE_CLE.test(cle)) {
    return repondre({ error: "champs_manquants" }, 422, cors);
  }

  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, cleService);
  const maintenant = new Date();
  const nowIso = maintenant.toISOString();
  const aujourdhui = nowIso.slice(0, 10);

  // Limite du formulaire, en base (empreinte de l'adresse seulement).
  try {
    const { data: ok, error } = await supabase.rpc("neuf_3d_formulaire", {
      p_ip: (await sha256(cleService + "|" + adresseIp(req))).slice(0, 32),
    });
    if (error) throw error;
    if (ok === false) return repondre({ error: "trop_de_demandes" }, 429, cors);
  } catch (_) {
    return repondre({ error: "indisponible" }, 503, cors);
  }

  // Programme montré sur le site seulement (v5) : nom et ville lus en base d'après la clé.
  let nomProg = programme, villeProg = ville;
  try {
    const { data: pr, error } = await supabase.rpc("neuf_3d_programme", { p_cle: cle });
    if (error) throw error;
    if (!pr?.nom) return repondre({ error: "inconnu" }, 404, cors);
    nomProg = String(pr.nom);
    villeProg = pr.ville ? String(pr.ville) : villeProg;
  } catch (_) {
    return repondre({ error: "indisponible" }, 503, cors);
  }
  const quoi = nomProg ? `programme ${nomProg}${villeProg ? " à " + villeProg : ""}` : `programme ${cle}`;
  const trace = `[${aujourdhui}] Formulaire visite 3D du site : ${quoi}. Accord de recontact donné.`;

  let contactId: string | null = null;
  try {
    // Fiche existante (même mail, sinon même téléphone) : on la rattache, jamais de doublon.
    let existant: any = null;
    const { data: parMail } = await supabase.from("contacts").select(CHAMPS_CONTACT).ilike("email", email).limit(1);
    if (parMail?.length) existant = parMail[0];
    if (!existant) {
      const { data: parTel } = await supabase.from("contacts").select(CHAMPS_CONTACT).eq("telephone_norm", telNorm).limit(1);
      if (parTel?.length) existant = parTel[0];
    }

    if (!existant) {
      const ligne = {
        nom: prenom, prenom, email, telephone: formatTel(telephone),
        lieu: villeProg || null,
        message: `Demande de visite 3D sur le site : ${quoi}.`,
        date_lead: aujourdhui,
        statut: "Nouveau",
        source: SOURCE, vendeur: VENDEUR,
        recu_le: nowIso,
        vendeur_depuis: nowIso,
        recu_par: [{ vendeur: VENDEUR, le: nowIso }],
        paternite_geree: true,
        notes: trace,
      };
      const { data: cr, error } = await supabase.rpc("contact_creer_si_absent", {
        p_email: email, p_tel_norm: telNorm, p_row: ligne,
      });
      if (error || !cr?.id) throw error || new Error("création impossible");
      contactId = cr.id;
      if (!cr.cree) {
        // Créée entre-temps par un autre envoi : on la traite comme une fiche existante.
        const { data: deja } = await supabase.from("contacts").select(CHAMPS_CONTACT).eq("id", cr.id).limit(1);
        existant = deja?.[0] || null;
      }
    }

    if (existant) {
      contactId = existant.id;
      // Règle d'Alex du 27/11/2026 (« Reste chez le vendeur ») : une fiche qui a déjà un vendeur le garde,
      // le formulaire du site ne touche pas à la paternité ; on note seulement le retour et la fiche
      // remonte en tête de liste (recu_le), comme tout client qui revient. Une fiche sans vendeur passe
      // par la porte de paternité de la base et va chez Alexandre, comme une fiche nouvelle.
      let mention = "";
      const maj: Record<string, unknown> = {};
      const vendeurActuel = String(existant.vendeur ?? "").trim();
      if (vendeurActuel) {
        mention = ` — suivi par ${vendeurActuel}, vendeur inchangé`;
        maj.recu_le = nowIso;
      } else {
        try {
          const { data: pat } = await supabase.rpc("paternite_recevoir", {
            p_contact: existant.id, p_vendeur: VENDEUR, p_source: SOURCE,
          });
          mention = pat?.mention || "";
        } catch (_) { mention = " — paternité non mise à jour (erreur base)"; }
      }
      maj.notes = (existant.notes ? existant.notes + "\n" : "") + trace + mention;
      if (!existant.nom_confirme && !existant.prenom) maj.prenom = prenom;
      // Une fiche « Perdu » qui revient par le site repasse en « Nouveau » (Alex, 27/11/2026 : « repasse en
      // statut actif »). Aucun autre statut n'est touché.
      if (existant.statut === "Perdu") {
        maj.statut = "Nouveau";
        maj.notes = String(maj.notes) + `\n[${aujourdhui}] Statut repassé de Perdu à Nouveau par le formulaire du site.`;
      }
      await supabase.from("contacts").update(maj).eq("id", existant.id);
    }
  } catch (_) {
    return repondre({ error: "enregistrement_impossible" }, 502, cors);
  }

  // Jeton remis au navigateur ; la base n'en garde que l'empreinte.
  const octets = crypto.getRandomValues(new Uint8Array(24));
  const jeton = Array.from(octets).map((b) => b.toString(16).padStart(2, "0")).join("");
  const { error: errJeton } = await supabase.rpc("neuf_3d_jeton_creer", {
    p_empreinte: await sha256(jeton), p_contact: contactId, p_programme: cle,
  });
  if (errJeton) return repondre({ error: "enregistrement_impossible" }, 502, cors);

  // Jamais « fiche créée » ou « déjà en base » : personne ne doit pouvoir savoir si une adresse est cliente.
  return repondre({ jeton }, 200, cors);
}

async function fichier(req: Request, cors: Record<string, string>) {
  const q = new URL(req.url).searchParams;
  const cle = (q.get("p") || "").trim().toLowerCase();
  const lot = (q.get("l") || "").trim().toLowerCase();
  const jeton = (q.get("t") || "").trim().toLowerCase();
  if (!RE_CLE.test(cle) || (lot && !RE_CLE.test(lot))) return repondre({ error: "inconnu" }, 404, cors);
  // Les plans d'un logement exigent le jeton du formulaire ; l'immeuble est ouvert à tous (Alex, 27/11/2026).
  const jetonValide = /^[0-9a-f]{48}$/.test(jeton);
  if (lot && !jetonValide) return repondre({ error: "jeton" }, 401, cors);

  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, cleService);

  // Plan du promoteur (v5) : jeton obligatoire. Image convertie par le robot de pige, rangée dans
  // l'espace privé plans2d ; la page reçoit un lien temporaire de 5 minutes vers la page demandée.
  if (q.get("doc") === "plan") {
    if (!lot) return repondre({ error: "inconnu" }, 404, cors);
    const page = Number(q.get("page") || "1");
    if (!Number.isInteger(page) || page < 1 || page > 8) return repondre({ error: "inconnu" }, 404, cors);
    let pl: any = null;
    try {
      const { data, error } = await supabase.rpc("neuf_2d_plan", {
        p_programme: cle,
        p_lot: lot,
        p_page: page,
        p_empreinte: await sha256(jeton),
        p_ip: (await sha256(cleService + "|" + adresseIp(req))).slice(0, 32),
      });
      if (error) throw error;
      pl = data;
    } catch (_) {
      return repondre({ error: "indisponible" }, 503, cors);
    }
    if (pl?.statut === "jeton") return repondre({ error: "jeton" }, 401, cors);
    if (pl?.statut === "limite") return repondre({ error: "trop_de_demandes" }, 429, cors);
    if (pl?.statut !== "ok" || !pl.chemin) return repondre({ error: "inconnu" }, 404, cors);

    const urlPlan = await lienSigne(supabase, ESPACE_PLANS, pl.chemin);
    if (!urlPlan) return repondre({ error: "reessayer" }, 503, cors);
    return repondre({ url: urlPlan, expire: DUREE_LIEN, pages: pl.pages }, 200, cors);
  }

  let res: any = null;
  try {
    const { data, error } = await supabase.rpc("neuf_3d_acces", {
      p_programme: cle,
      p_lot: lot || null,
      p_empreinte: jetonValide ? await sha256(jeton) : null,
      // Empreinte de l'adresse IP : la base ne garde jamais l'adresse elle-même.
      p_ip: (await sha256(cleService + "|" + adresseIp(req))).slice(0, 32),
    });
    if (error) throw error;
    res = data;
  } catch (_) {
    return repondre({ error: "indisponible" }, 503, cors);
  }

  if (res?.statut === "jeton") return repondre({ error: "jeton" }, 401, cors);
  if (res?.statut === "limite") return repondre({ error: "trop_de_demandes" }, 429, cors);
  if (res?.statut !== "ok" || !res.fichier) return repondre({ error: "inconnu" }, 404, cors);

  // Immeuble (sans lot) : lien gardé en mémoire 4 minutes, le même pour tous les visiteurs.
  const maintenantMs = Date.now();
  if (!lot) {
    const c = cacheImmeuble.get(res.fichier);
    if (c && c.jusqua > maintenantMs) {
      return repondre({ url: c.url, expire: Math.floor((c.jusqua - maintenantMs) / 1000) + 60 }, 200, cors);
    }
  }
  const url = await lienSigne(supabase, ESPACE, res.fichier);
  if (!url) return repondre({ error: "reessayer" }, 503, cors);
  if (!lot) {
    if (cacheImmeuble.size > 200) cacheImmeuble.clear();
    cacheImmeuble.set(res.fichier, { url, jusqua: maintenantMs + CACHE_IMMEUBLE_MS });
  }
  return repondre({ url, expire: DUREE_LIEN }, 200, cors);
}

Deno.serve(async (req: Request) => {
  const cors = entetesCors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method === "POST") return inscrire(req, cors);
  if (req.method === "GET") return fichier(req, cors);
  return repondre({ error: "method_not_allowed" }, 405, cors);
});
