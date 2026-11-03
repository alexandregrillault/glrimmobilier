// Robot Instagram de Quoi de neuf (demande d'Alex du 03/11/2026)
//
// Webhook de l'API Instagram (connexion Instagram, accès standard : le compte
// @quoideneuf.immo seulement). Deux cas :
//  - un commentaire qui contient « plans » sous une publication : réponse publique
//    courte + message privé avec le lien du formulaire www.glrimmobilier.com/plans/ ;
//  - un message privé reçu : le lien du formulaire, une seule fois par personne
//    et par semaine (ou chaque fois que le message parle de plans).
// Le formulaire crée la fiche dans le CRM (edge function qdn-plans). Ici, aucune
// donnée personnelle n'est envoyée au CRM.
//
// Clés lues dans app_secrets (jamais dans ce dépôt public) :
//   ig_app_secret      secret de l'application Meta (signature des appels)
//   ig_verify_token    mot de passe choisi pour l'abonnement au webhook
//   ig_access_token    jeton longue durée du compte Instagram (60 jours, renouvelé ici)
// Journal : table qdn_instagram_evenements.

import { createClient } from "npm:@supabase/supabase-js@2";

const GRAPH = "https://graph.instagram.com/v24.0";
const LIEN = "https://www.glrimmobilier.com/plans/?src=instagram";
const RENOUVELER_APRES_J = 30;
const RELANCE_MESSAGE_J = 7;
const CONSERVATION_J = 365;

const REPONSES_PUBLIQUES = [
  "C'est envoyé en message privé.",
  "Je t'ai écrit en message privé.",
  "Regarde tes messages privés, c'est parti.",
];

const MESSAGE_COMMENTAIRE = (lien: string) =>
  "Salut, c'est Alto de Quoi de neuf. Voici le lien pour recevoir les plans des programmes neufs de ton secteur : " + lien +
  "\n\nTu indiques ta ville et ton numéro, et un conseiller de GLR Immobilier, notre partenaire, t'envoie la sélection.";

const MESSAGE_PRIVE = (lien: string) =>
  "Salut, merci pour ton message. Si tu veux les plans des programmes neufs de ton secteur, c'est ici : " + lien +
  "\n\nUn conseiller de GLR Immobilier, notre partenaire, te recontacte. Pour le reste, on te répond ici très vite.";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function secrets(): Promise<Record<string, { value: string; updated_at: string }>> {
  const { data } = await supabase.from("app_secrets").select("name, value, updated_at").like("name", "ig_%");
  const s: Record<string, { value: string; updated_at: string }> = {};
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

// Le jeton longue durée expire au bout de 60 jours : on le renouvelle passé 30 jours.
async function jeton(s: Record<string, { value: string; updated_at: string }>): Promise<string | null> {
  const t = s.ig_access_token;
  if (!t?.value) return null;
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
  const r = await fetch(`${GRAPH}/${chemin}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${jt}` },
    body: JSON.stringify(corps),
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, statut: r.status, reponse: j };
}

const parleDePlans = (t: string) => /(^|[^a-z])plans?([^a-z]|$)/i.test(t);

// Enregistre l'événement ; renvoie false s'il a déjà été traité (Meta renvoie parfois deux fois).
async function nouveau(ev: Record<string, unknown>): Promise<boolean> {
  const { error } = await supabase.from("qdn_instagram_evenements").insert(ev);
  return !error;
}

async function noter(id: string, repondu: boolean, resultat: unknown) {
  await supabase.from("qdn_instagram_evenements").update({ repondu, resultat }).eq("id", id);
}

async function traiterCommentaire(compte: string, v: any, jt: string) {
  const texte = String(v?.text || "");
  const auteur = v?.from?.id ? String(v.from.id) : null;
  if (!v?.id || !auteur || auteur === compte || !parleDePlans(texte)) return;
  const ok = await nouveau({ id: String(v.id), type: "commentaire", ig_user: auteur, ig_pseudo: v.from?.username || null, texte: texte.slice(0, 500), media_id: v.media?.id || null });
  if (!ok) return;
  const lien = LIEN + (v.media?.id ? "&ref=" + encodeURIComponent(v.media.id) : "");
  const prive = await appel(`${compte}/messages`, jt, { recipient: { comment_id: String(v.id) }, message: { text: MESSAGE_COMMENTAIRE(lien) } });
  const pub = await appel(`${v.id}/replies`, jt, { message: REPONSES_PUBLIQUES[Math.floor(Math.random() * REPONSES_PUBLIQUES.length)] });
  await noter(String(v.id), prive.ok, { prive, public: pub });
}

async function traiterMessage(compte: string, m: any, jt: string) {
  const exp = m?.sender?.id ? String(m.sender.id) : null;
  const msg = m?.message;
  if (!exp || exp === compte || !msg?.mid || msg.is_echo) return;
  const texte = String(msg.text || "");
  // Une fois par personne et par semaine, sauf si elle parle de plans.
  if (!parleDePlans(texte)) {
    const depuis = new Date(Date.now() - RELANCE_MESSAGE_J * 86400000).toISOString();
    const { data } = await supabase.from("qdn_instagram_evenements").select("id").eq("ig_user", exp).eq("repondu", true).gte("recu_le", depuis).limit(1);
    if (data?.length) return;
  }
  const ok = await nouveau({ id: String(msg.mid), type: "message", ig_user: exp, texte: texte.slice(0, 500) });
  if (!ok) return;
  const r = await appel(`${compte}/messages`, jt, { recipient: { id: exp }, message: { text: MESSAGE_PRIVE(LIEN) } });
  await noter(String(msg.mid), r.ok, r);
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
  // Conservation annoncée dans les mentions légales : 12 mois au plus.
  try {
    await supabase.from("qdn_instagram_evenements").delete().lt("recu_le", new Date(Date.now() - CONSERVATION_J * 86400000).toISOString());
  } catch (_) { /* on réessaiera au prochain appel */ }
  // Toujours 200 : sinon Meta renvoie l'événement et finit par couper l'abonnement.
  return new Response("ok", { status: 200 });
});
