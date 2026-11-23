// Robot Instagram de Quoi de neuf (demande d'Alex du 03/11/2026)
//
// Webhook de l'API Instagram (connexion Instagram, accès standard : le compte
// @quoideneuf.immo seulement).
// v19 (23/11/2026, décision d'Alex : « je veux simplement que le robot envoie le message ») :
// plus de questionnaire. Le robot envoie un seul message, le même pour tout le monde (parcours.ts) :
//  - un commentaire qui contient « plan » ou « plans » : le message en réponse privée au commentaire,
//    jamais de réponse publique (retirée le 06/11/2026 : Instagram masquait tout le fil) ;
//  - un message privé qui parle de plans : le même message ;
//  - un autre message privé : rien, c'est un humain qui répond ;
//  - « STOP » : le robot s'arrête.
// Le message porte un bouton « Voir le planning » vers le planning de Théophile. Si Instagram
// refuse le bouton, le même texte part avec l'adresse du planning écrite. La fiche est créée par
// la page de rendez-vous quand la personne valide son créneau : le robot ne crée aucune fiche.
//
// Clés lues dans app_secrets (jamais dans ce dépôt public) :
//   ig_app_secret      secret de l'application Meta (signature des appels)
//   ig_verify_token    mot de passe choisi pour l'abonnement au webhook
//   ig_access_token    jeton longue durée du compte Instagram (60 jours, renouvelé ici)
// Tables : qdn_instagram_evenements (ne jamais traiter deux fois le même événement),
// qdn_instagram_conversations (où en est chaque personne : message envoyé, arrêt demandé).

import { createClient } from "npm:@supabase/supabase-js@2";
import { demarrerDepuisCommentaire, repondre, parleDePlans, enTexte } from "./parcours.ts";
import type { Conversation, Message } from "./parcours.ts";

// Connexion unifiée (seule voie ouverte aux nouvelles applications depuis 2026) : jeton
// d'utilisateur système « EAA… » sans expiration, sur graph.facebook.com. Un jeton Instagram
// « IG… » (ancienne connexion Instagram) passe par graph.instagram.com. Mêmes chemins d'appel.
const VERSION = "v24.0";
const graph = (jt: string) => `https://graph.${jt.startsWith("IG") ? "instagram" : "facebook"}.com/${VERSION}`;
const RENOUVELER_APRES_J = 30;
const CONSERVATION_J = 365;
const ABANDON_J = 7;

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

type Secrets = Record<string, { value: string; updated_at: string }>;

// Clés gardées 5 minutes en mémoire : une lecture de base en moins à chaque message (réponses plus rapides).
let CLES: { s: Secrets; t: number } | null = null;
async function secrets(): Promise<Secrets> {
  if (CLES && Date.now() - CLES.t < 300000) return CLES.s;
  const { data } = await supabase.from("app_secrets").select("name, value, updated_at").in("name", ["ig_app_secret", "ig_verify_token", "ig_access_token"]);
  const s: Secrets = {};
  (data || []).forEach((r: any) => (s[r.name] = { value: r.value, updated_at: r.updated_at }));
  if (s.ig_app_secret && s.ig_access_token) CLES = { s, t: Date.now() };
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

// Un message à boutons part comme « modèle à boutons » d'Instagram : le texte (640 caractères au
// plus), puis jusqu'à trois boutons qui ouvrent une page.
function formatMessage(m: Message) {
  if (m.boutons && m.boutons.length) {
    return { attachment: { type: "template", payload: { template_type: "button", text: m.text,
      buttons: m.boutons.map((b) => ({ type: "web_url", url: b.url, title: b.title })) } } };
  }
  return { text: m.text };
}

// Envoie un message à `destinataire` (une personne, ou un commentaire pour la réponse privée).
// Boutons refusés par Instagram : le même message repart en texte, avec les adresses écrites.
async function envoyer(compte: string, jt: string, destinataire: Record<string, string>, m: Message) {
  let e = await appel(`${compte}/messages`, jt, { recipient: destinataire, message: formatMessage(m) });
  let forme = m.boutons && m.boutons.length ? "boutons" : "texte";
  if (!e.ok && forme === "boutons") {
    const refus = { statut: e.statut, erreur: (e.reponse as any)?.error?.message || null };
    e = await appel(`${compte}/messages`, jt, { recipient: destinataire, message: { text: enTexte(m) } });
    return { ok: e.ok, statut: e.statut, forme: "texte avec adresses", boutons_refuses: refus, erreur: e.ok ? null : (e.reponse as any)?.error?.message || null };
  }
  return { ok: e.ok, statut: e.statut, forme, erreur: e.ok ? null : (e.reponse as any)?.error?.message || null };
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

async function traiterCommentaire(compte: string, v: any, jt: string) {
  const texte = String(v?.text || "");
  const auteur = v?.from?.id ? String(v.from.id) : null;
  if (!v?.id || !auteur || auteur === compte || !parleDePlans(texte)) return;
  const pseudo = v.from?.username || null;
  const ok = await nouveau({ id: String(v.id), type: "commentaire", ig_user: auteur, ig_pseudo: pseudo, texte: texte.slice(0, 500), media_id: v.media?.id || null });
  if (!ok) return;
  const r = demarrerDepuisCommentaire(pseudo);
  // Réponse privée seulement, un seul message : jamais de réponse publique sous le commentaire.
  const prive = await envoyer(compte, jt, { comment_id: String(v.id) }, r.messages[0]);
  if (prive.ok && r.conv) {
    await ecrireConversation(auteur, r.conv, { origine: "commentaire", media_id: v.media?.id || null, debut_le: new Date().toISOString(), contact_id: null });
  }
  await noter(String(v.id), prive.ok, { prive });
}

async function traiterMessage(compte: string, m: any, jt: string) {
  const exp = m?.sender?.id ? String(m.sender.id) : null;
  const msg = m?.message;
  if (!exp || exp === compte || !msg?.mid || msg.is_echo) return;
  // Le texte des messages n'est pas gardé dans le journal : il peut contenir un téléphone ou un e-mail.
  // Journal et conversation lus en même temps (une attente au lieu de deux).
  const [ok, ligne] = await Promise.all([nouveau({ id: String(msg.mid), type: "message", ig_user: exp, texte: null }), lireConversation(exp)]);
  if (!ok) return;

  const conv: Conversation | null = ligne ? { etape: ligne.etape, reponses: ligne.reponses || {}, essais: ligne.essais || 0 } : null;
  const r = repondre(conv, String(msg.text || ""), msg.quick_reply?.payload || null);

  const envois: unknown[] = [];
  for (const mm of r.messages) envois.push(await envoyer(compte, jt, { id: exp }, mm));
  if (r.conv && r.conv !== conv) {
    await ecrireConversation(exp, r.conv, ligne ? {} : { origine: "message", debut_le: new Date().toISOString() });
  }
  await noter(String(msg.mid), envois.every((e: any) => e.ok), { envois, etape: r.conv ? r.conv.etape : null });
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
      try { await traiterMessage(compte, m, jt); } catch (_) { /* idem */ }
    }
  }
  // Conservation annoncée dans les mentions légales : 12 mois au plus. Faite un appel sur vingt
  // seulement (inutile à chaque message, et elle retardait la réponse suivante).
  if (Math.random() < 0.05) try {
    const limite = new Date(Date.now() - CONSERVATION_J * 86400000).toISOString();
    await Promise.all([
      supabase.from("qdn_instagram_evenements").delete().lt("recu_le", limite),
      supabase.from("qdn_instagram_conversations").delete().lt("maj_le", limite),
      // Ancien questionnaire abandonné en cours de route : rien n'est gardé au-delà de 7 jours.
      supabase.from("qdn_instagram_conversations").delete()
        .not("etape", "in", "(planning,fini,refus,ferme)").lt("maj_le", new Date(Date.now() - ABANDON_J * 86400000).toISOString()),
    ]);
  } catch (_) { /* on réessaiera à un prochain appel */ }
  // Toujours 200 : sinon Meta renvoie l'événement et finit par couper l'abonnement.
  return new Response("ok", { status: 200 });
});
