// Robot Instagram de Quoi de neuf (demande d'Alex du 03/11/2026)
//
// Webhook de l'API Instagram (connexion Instagram, accès standard : le compte
// @quoideneuf.immo seulement). Le questionnaire se fait dans les messages privés,
// question par question (questionnaire.ts) :
//  - un commentaire qui contient « plans » : réponse publique courte + première question
//    en réponse privée au commentaire ;
//  - un message privé : la réponse à la question en cours, ou, sans conversation,
//    une invitation à recevoir les plans.
// À la fin, avec l'accord de la personne, la fiche est créée dans le CRM par lead-inbound
// (vendeur theophile, source « Quoi de neuf Instagram »), comme le formulaire du site.
//
// Clés lues dans app_secrets (jamais dans ce dépôt public) :
//   ig_app_secret      secret de l'application Meta (signature des appels)
//   ig_verify_token    mot de passe choisi pour l'abonnement au webhook
//   ig_access_token    jeton longue durée du compte Instagram (60 jours, renouvelé ici)
//   lead_inbound_token jeton de lead-inbound
// Tables : qdn_instagram_evenements (ne jamais traiter deux fois le même événement),
// qdn_instagram_conversations (étape et réponses de chaque personne).

import { createClient } from "npm:@supabase/supabase-js@2";
import { demarrerDepuisCommentaire, repondre, parleDePlans, Q, lienPlanningPersonnel } from "./questionnaire.ts";
import type { Conversation, Message } from "./questionnaire.ts";

// Connexion unifiée (seule voie ouverte aux nouvelles applications depuis 2026) : jeton
// d'utilisateur système « EAA… » sans expiration, sur graph.facebook.com. Un jeton Instagram
// « IG… » (ancienne connexion Instagram) passe par graph.instagram.com. Mêmes chemins d'appel.
const VERSION = "v24.0";
const graph = (jt: string) => `https://graph.${jt.startsWith("IG") ? "instagram" : "facebook"}.com/${VERSION}`;
const RENOUVELER_APRES_J = 30;
const CONSERVATION_J = 365;
const FENETRE_H = 24;
const ABANDON_J = 7;
const VENDEUR = "theophile"; // leads Quoi de neuf chez Théophile (décision d'Alex du 03/11/2026)
const SOURCE = "Quoi de neuf Instagram";

const REPONSES_PUBLIQUES = [
  "C'est envoyé en message privé.",
  "Je t'ai écrit en message privé.",
  "Regarde tes messages privés, c'est parti.",
];

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

type Secrets = Record<string, { value: string; updated_at: string }>;

async function secrets(): Promise<Secrets> {
  const { data } = await supabase.from("app_secrets").select("name, value, updated_at").in("name", ["ig_app_secret", "ig_verify_token", "ig_access_token", "lead_inbound_token"]);
  const s: Secrets = {};
  (data || []).forEach((r: any) => (s[r.name] = { value: r.value, updated_at: r.updated_at }));
  return s;
}

async function signatureValide(brut: string, entete: string | null, secret: string): Promise<boolean> {
  if (!entete || !entete.startsWith("sha256=")) return false;
  const cle = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", cle, new TextEncoder().encode(brut)));
  const attendu = Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
  const recu = entete.slice(7);
  if (recu.length !== attendu.length) return false;
  let diff = 0;
  for (let i = 0; i < recu.length; i++) diff |= recu.charCodeAt(i) ^ attendu.charCodeAt(i);
  return diff === 0;
}

// Un jeton Instagram expire au bout de 60 jours : on le renouvelle passé 30 jours.
// Le jeton d'utilisateur système de la connexion unifiée n'expire pas.
async function jeton(s: Secrets): Promise<string | null> {
  const t = s.ig_access_token;
  if (!t?.value) return null;
  if (!t.value.startsWith("IG")) return t.value;
  const age = (Date.now() - new Date(t.updated_at).getTime()) / 86400000;
  if (age > RENOUVELER_APRES_J) {
    try {
      const r = await fetch(`https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=${encodeURIComponent(t.value)}`);
      const j = await r.json();
      if (j.access_token) {
        await supabase.from("app_secrets").update({ value: j.access_token, updated_at: new Date().toISOString() }).eq("name", "ig_access_token");
        return j.access_token;
      }
    } catch (_) { /* on garde l'ancien tant qu'il est valable */ }
  }
  return t.value;
}

async function appel(chemin: string, jt: string, corps: unknown) {
  const r = await fetch(`${graph(jt)}/${chemin}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${jt}` },
    body: JSON.stringify(corps),
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, statut: r.status, reponse: j };
}

function formatMessage(m: Message) {
  if (m.carte) {
    return { attachment: { type: "template", payload: { template_type: "generic", elements: [{
      title: m.carte.titre, subtitle: m.carte.sousTitre,
      buttons: m.carte.boutons.map((b) => ({ type: "web_url", url: b.url, title: b.title })),
    }] } } };
  }
  return m.quick_replies
    ? { text: m.text, quick_replies: m.quick_replies.map((b) => ({ content_type: "text", title: b.title, payload: b.payload })) }
    : { text: m.text };
}

// Enregistre l'événement ; renvoie false s'il a déjà été traité (Meta renvoie parfois deux fois).
async function nouveau(ev: Record<string, unknown>): Promise<boolean> {
  const { error } = await supabase.from("qdn_instagram_evenements").insert(ev);
  return !error;
}

async function noter(id: string, repondu: boolean, resultat: unknown) {
  await supabase.from("qdn_instagram_evenements").update({ repondu, resultat }).eq("id", id);
}

async function lireConversation(igUser: string) {
  const { data } = await supabase.from("qdn_instagram_conversations").select("*").eq("ig_user", igUser).maybeSingle();
  return data;
}

async function ecrireConversation(igUser: string, conv: Conversation, extra: Record<string, unknown> = {}) {
  await supabase.from("qdn_instagram_conversations").upsert({
    ig_user: igUser, etape: conv.etape, reponses: conv.reponses, essais: conv.essais, maj_le: new Date().toISOString(), ...extra,
  });
}

// Fin du questionnaire avec accord : la fiche part au CRM par lead-inbound (dédoublonnage, paternité).
async function creerFiche(s: Secrets, r: Record<string, string>): Promise<string | null> {
  if (!s.lead_inbound_token?.value) return null;
  const aujourdhui = new Date().toISOString().slice(0, 10);
  const corps = [
    `Demande reçue en message privé Instagram (questionnaire Quoi de neuf${r.pseudo ? ", @" + r.pseudo : ""})`,
    ``,
    `Prénom : ${r.prenom}`,
    `Téléphone : ${r.telephone}`,
    `Email : ${r.email}`,
    `Secteur recherché : ${r.zone}`,
    r.typologie ? `Typologie : ${r.typologie}` : null,
    r.budget ? `Budget : ${r.budget}` : null,
    ``,
    `Accord de recontact par GLR Immobilier donné le ${aujourdhui}.`,
  ].filter((l) => l !== null).join("\n");
  const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/lead-inbound?token=${s.lead_inbound_token.value}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      vendeur: VENDEUR, from: r.email, from_name: r.prenom, subject: `Instagram Quoi de neuf — ${r.prenom}`, plain: corps,
      nom: r.prenom, email: r.email, telephone: r.telephone, budget: r.budget || null, lieu: r.zone, typologie: r.typologie || null,
    }),
  });
  const resultat: any = await res.json().catch(() => null);
  if (!resultat?.id) return null;
  try {
    const { data: actuel } = await supabase.from("contacts").select("notes").eq("id", resultat.id).single();
    const maj: Record<string, unknown> = {};
    if (resultat.status === "created") maj.source = SOURCE;
    const trace = `[${aujourdhui}] Questionnaire Instagram Quoi de neuf${r.pseudo ? " (@" + r.pseudo + ")" : ""} : ${r.zone}${r.typologie ? ", " + r.typologie : ""}${r.budget ? ", " + r.budget : ""}. Accord de recontact donné.`;
    maj.notes = actuel?.notes ? actuel.notes + "\n" + trace : trace;
    await supabase.from("contacts").update(maj).eq("id", resultat.id);
  } catch (_) { /* la fiche existe : on n'échoue pas pour un affinage */ }
  return resultat.id;
}

// Lien de rendez-vous personnel de la fiche (créé avec le lead, table rdv_liens) : la page montre
// le planning du conseiller et la personne n'a pas à retaper ses coordonnées. Sans lien valable,
// le message garde le lien public du planning de Théophile.
// Un lien qui porte déjà un rendez-vous passé (fiche existante, test du 03/11/2026 : la page proposait
// de valider un ancien rendez-vous de septembre) n'est pas renvoyé : on crée un lien neuf pour la fiche.
async function lienRdv(contactId: string): Promise<string | null> {
  try {
    const { data } = await supabase.from("rdv_liens").select("token, contexte, vendeur, rdv").eq("contact_id", contactId)
      .gt("expires_at", new Date().toISOString()).order("created_at", { ascending: false }).limit(1);
    const l: any = data?.[0];
    if (!l?.token) return null;
    const contexte = { ...(l.contexte || {}), source: SOURCE };
    const debut = l.rdv?.debut ? new Date(l.rdv.debut).getTime() : null;
    if (debut === null || debut > Date.now()) {
      await supabase.from("rdv_liens").update({ contexte }).eq("token", l.token);
      return l.token;
    }
    const token = Array.from(crypto.getRandomValues(new Uint8Array(12))).map((b) => b.toString(16).padStart(2, "0")).join("");
    const { error } = await supabase.from("rdv_liens").insert({ token, contact_id: contactId, vendeur: l.vendeur, origine: "auto_lead", contexte });
    return error ? null : token;
  } catch (_) { return null; }
}

async function traiterCommentaire(compte: string, v: any, jt: string) {
  const texte = String(v?.text || "");
  const auteur = v?.from?.id ? String(v.from.id) : null;
  if (!v?.id || !auteur || auteur === compte || !parleDePlans(texte)) return;
  const pseudo = v.from?.username || null;
  const ok = await nouveau({ id: String(v.id), type: "commentaire", ig_user: auteur, ig_pseudo: pseudo, texte: texte.slice(0, 500), media_id: v.media?.id || null });
  if (!ok) return;
  const r = demarrerDepuisCommentaire(pseudo);
  const prive = await appel(`${compte}/messages`, jt, { recipient: { comment_id: String(v.id) }, message: formatMessage(r.messages[0]) });
  const pub = await appel(`${v.id}/replies`, jt, { message: REPONSES_PUBLIQUES[Math.floor(Math.random() * REPONSES_PUBLIQUES.length)] });
  if (prive.ok) {
    await ecrireConversation(auteur, r.conv, { origine: "commentaire", media_id: v.media?.id || null, debut_le: new Date().toISOString(), contact_id: null });
  }
  await noter(String(v.id), prive.ok, { prive, public: pub });
}

async function traiterMessage(compte: string, m: any, jt: string, s: Secrets) {
  const exp = m?.sender?.id ? String(m.sender.id) : null;
  const msg = m?.message;
  if (!exp || exp === compte || !msg?.mid || msg.is_echo) return;
  // Le texte des messages n'est pas gardé dans le journal : il peut contenir un téléphone ou un e-mail.
  const ok = await nouveau({ id: String(msg.mid), type: "message", ig_user: exp, texte: null });
  if (!ok) return;

  const ligne = await lireConversation(exp);
  const conv: Conversation | null = ligne ? { etape: ligne.etape, reponses: ligne.reponses || {}, essais: ligne.essais || 0 } : null;
  const expire = ligne ? Date.now() - new Date(ligne.maj_le).getTime() > FENETRE_H * 3600000 : false;
  const r = repondre(conv, String(msg.text || ""), msg.quick_reply?.payload || null, expire);

  let extra: Record<string, unknown> = ligne ? {} : { origine: "message", debut_le: new Date().toISOString() };
  let conv2 = r.conv;
  let messages = r.messages;
  if (r.creerFiche) {
    // La fiche entre dans le CRM d'abord, puis la personne reçoit son lien pour choisir le créneau d'appel.
    const contact = await creerFiche(s, r.conv.reponses);
    const jetonRdv = contact ? await lienRdv(contact) : null;
    if (jetonRdv) messages = [Q.merci(r.conv.reponses.prenom || ""), Q.planning(lienPlanningPersonnel(jetonRdv))];
    // Une fois la fiche créée, on ne garde ici que le prénom et le pseudo.
    conv2 = { ...r.conv, reponses: { prenom: r.conv.reponses.prenom || "", pseudo: r.conv.reponses.pseudo || "" } };
    extra = { ...extra, contact_id: contact };
  }

  const envois = [];
  for (const mm of messages) {
    let e = await appel(`${compte}/messages`, jt, { recipient: { id: exp }, message: formatMessage(mm) });
    // Carte refusée par Instagram : on retombe sur le texte avec le lien du premier bouton.
    if (!e.ok && mm.carte) e = await appel(`${compte}/messages`, jt, { recipient: { id: exp }, message: { text: `${mm.text} ${mm.carte.boutons[0].url}` } });
    envois.push(e);
  }
  if (r.messages.length || r.conv !== conv) await ecrireConversation(exp, conv2, extra);
  await noter(String(msg.mid), envois.every((e) => e.ok), { envois: envois.map((e) => ({ ok: e.ok, statut: e.statut })), etape: conv2.etape, fiche: !!r.creerFiche });
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const s = await secrets();

  // Abonnement au webhook (Meta vérifie l'adresse une fois).
  if (req.method === "GET") {
    if (url.searchParams.get("hub.mode") === "subscribe" && s.ig_verify_token?.value &&
        url.searchParams.get("hub.verify_token") === s.ig_verify_token.value) {
      return new Response(url.searchParams.get("hub.challenge") || "", { status: 200 });
    }
    return new Response("Forbidden", { status: 403 });
  }
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const brut = await req.text();
  if (!s.ig_app_secret?.value || !(await signatureValide(brut, req.headers.get("x-hub-signature-256"), s.ig_app_secret.value))) {
    return new Response("Unauthorized", { status: 401 });
  }
  let payload: any;
  try { payload = JSON.parse(brut); } catch { return new Response("ok", { status: 200 }); }

  const jt = await jeton(s);
  if (!jt) return new Response("ok", { status: 200 });

  for (const entry of payload?.entry || []) {
    const compte = String(entry.id || "");
    for (const c of entry.changes || []) {
      if (c.field === "comments") {
        try { await traiterCommentaire(compte, c.value, jt); } catch (_) { /* un échec n'arrête pas les autres */ }
      }
    }
    for (const m of entry.messaging || []) {
      try { await traiterMessage(compte, m, jt, s); } catch (_) { /* idem */ }
    }
  }
  // Conservation annoncée dans les mentions légales : 12 mois au plus.
  try {
    const limite = new Date(Date.now() - CONSERVATION_J * 86400000).toISOString();
    await supabase.from("qdn_instagram_evenements").delete().lt("recu_le", limite);
    await supabase.from("qdn_instagram_conversations").delete().lt("maj_le", limite);
    // Questionnaire abandonné en cours de route : rien n'est gardé au-delà de 7 jours.
    await supabase.from("qdn_instagram_conversations").delete()
      .not("etape", "in", "(fini,refus,ferme)").lt("maj_le", new Date(Date.now() - ABANDON_J * 86400000).toISOString());
  } catch (_) { /* on réessaiera au prochain appel */ }
  // Toujours 200 : sinon Meta renvoie l'événement et finit par couper l'abonnement.
  return new Response("ok", { status: 200 });
});
