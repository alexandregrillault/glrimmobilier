// Visites 3D des programmes sur les pages ville du site (www.glrimmobilier.com/neuf/<ville>/<programme>/).
//
// Version 4, PRÉPARÉE le 27/11/2026, PAS ENCORE DÉPLOYÉE : plus de champ piège, anti-robots par le délai
// d'envoi (« delai_ms », 1,5 s minimum, absent accepté) ; téléphone « +33 (0)6… » normalisé. Version 3 en ligne :
// anciennes/index_v3.ts ; v2 : anciennes/index_v2.ts ; v1 : anciennes/index_v1.ts.
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
//    → 422 champs manquants, 429 trop d'envois, 502 enregistrement impossible.
//    Le lead est créé chez Alexandre (ou rattaché à la fiche existante, mêmes règles de paternité que
//    les autres leads), directement en base : AUCUN mail ni SMS n'est envoyé au client. On ne passe
//    pas par lead-inbound, qui envoie de lui-même un accusé avec un lien de rendez-vous.
//
// 2. Un fichier de la visite
//    GET ?p=<clé programme>                      → l'immeuble, sans jeton
//    GET ?p=<clé programme>&l=<clé lot>&t=<jeton> → les plans d'un logement, jeton obligatoire
//    → 200 { url, expire: 300 }  lien temporaire (5 minutes) vers la page HTML, à télécharger tout de suite
//      (le stockage sert le HTML en texte brut : la page l'affiche par un lien blob:, pas par iframe src=).
//    → 401 jeton absent, faux ou expiré pour un logement (la page montre le formulaire), 404 inconnu,
//      429 trop de demandes.
//    Limite contre l'aspiration (en base, neuf_3d_acces) : 40 fichiers par jeton et 60 par adresse, par jour.
//    À la première ouverture d'un logement, la base ajoute aux notes de la fiche du client une ligne
//    « [JJ/MM/AAAA] Visite 3D : lot A001 (T3, 61 m²), Esprit Valmy à Colombes » (une fois par logement).

import { createClient } from "npm:@supabase/supabase-js@2";

const VENDEUR = "Alexandre";             // « mets les leads chez moi » (Alex, 27/11/2026)
const SOURCE = "Site web";               // « source du lead mets juste site web » (Alex, 27/11/2026)
const DUREE_LIEN = 300;                  // secondes
const DELAI_MIN_MS = 1500;               // anti-robots : temps minimal entre affichage et envoi (accord avec Site)
const ESPACE = "plans3d";

const ORIGINES_AUTORISEES = [
  "https://www.glrimmobilier.com",
  "https://glrimmobilier.com",
];

// Formulaire : 3 envois par tranche de 10 minutes et par adresse (comme qdn-plans).
const FENETRE_MS = 10 * 60 * 1000;
const MAX_PAR_FENETRE = 3;
const historique = new Map<string, number[]>();

function tropDeEnvois(ip: string): boolean {
  const now = Date.now();
  const passages = (historique.get(ip) || []).filter((t) => now - t < FENETRE_MS);
  passages.push(now);
  historique.set(ip, passages);
  if (historique.size > 5000) historique.clear();
  return passages.length > MAX_PAR_FENETRE;
}

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

const CHAMPS_CONTACT = "id, notes, prenom, nom_confirme";

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

  const ip = adresseIp(req);
  if (tropDeEnvois(ip)) return repondre({ error: "trop_de_demandes" }, 429, cors);

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

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const maintenant = new Date();
  const nowIso = maintenant.toISOString();
  const aujourdhui = nowIso.slice(0, 10);
  // Nom et ville lus en base d'après la clé (migration 20261127_plans_3d_note.sql) ; le texte envoyé
  // par la page ne sert que de secours.
  let nomProg = programme, villeProg = ville;
  try {
    const { data: pr } = await supabase.rpc("neuf_3d_programme", { p_cle: cle });
    if (pr?.nom) { nomProg = String(pr.nom); villeProg = pr.ville ? String(pr.ville) : villeProg; }
  } catch (_) { /* secours : le texte de la page */ }
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
      // Porte unique de paternité de la base (mêmes règles que les autres leads). Elle n'envoie rien.
      let mention = "";
      try {
        const { data: pat } = await supabase.rpc("paternite_recevoir", {
          p_contact: existant.id, p_vendeur: VENDEUR, p_source: SOURCE,
        });
        mention = pat?.mention || "";
      } catch (_) { mention = " — paternité non mise à jour (erreur base)"; }
      const maj: Record<string, unknown> = { notes: (existant.notes ? existant.notes + "\n" : "") + trace + mention };
      if (!existant.nom_confirme && !existant.prenom) maj.prenom = prenom;
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

  const { data: lien, error: errLien } = await supabase.storage.from(ESPACE).createSignedUrl(res.fichier, DUREE_LIEN);
  if (errLien || !lien?.signedUrl) return repondre({ error: "inconnu" }, 404, cors);
  return repondre({ url: lien.signedUrl, expire: DUREE_LIEN }, 200, cors);
}

Deno.serve(async (req: Request) => {
  const cors = entetesCors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method === "POST") return inscrire(req, cors);
  if (req.method === "GET") return fichier(req, cors);
  return repondre({ error: "method_not_allowed" }, 405, cors);
});
