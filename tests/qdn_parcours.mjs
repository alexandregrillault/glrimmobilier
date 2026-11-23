// Test du robot Instagram de Quoi de neuf (supabase/functions/qdn-instagram/) : le parcours (parcours.ts),
// puis la fonction entière (index.ts) exécutée avec une base et un Instagram simulés.
// Lancer : ~/.local/bin/node tests/qdn_parcours.mjs
import { readFileSync, writeFileSync, mkdtempSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createHmac } from "node:crypto";
import { demarrerDepuisCommentaire, repondre, parleDePlans, veutArreter, enTexte, M, TEXTE_RDV, LIEN_PLANNING } from "../supabase/functions/qdn-instagram/parcours.ts";

let echecs = 0;
const ok = (cond, msg) => { if (!cond) { echecs++; console.log("ÉCHEC :", msg); } else console.log("ok :", msg); };
const DOSSIER = join(dirname(fileURLToPath(import.meta.url)), "..", "supabase", "functions", "qdn-instagram");

// ---- 1. Le parcours ----
ok(["PLANS", "Plans", "plan", "Plan.", "PLAN !", "#plans", "plans🙏", "les plans svp"].every(parleDePlans), "« plan » et « plans » déclenchent le robot");
ok(!["planning", "explanation", "bonjour"].some(parleDePlans), "« planning » ne déclenche pas");
ok(["stop", "STOP", "Stop !", " arrête "].every(veutArreter) && !veutArreter("ne t'arrête pas"), "« STOP » reconnu");

const m = M.rdv();
ok(m.text === TEXTE_RDV && /^Salut, c'est GLR Immobilier, le média Quoi de neuf\. 👋 /.test(m.text), "le message commence comme validé par Alex");
ok(/prends 10 minutes avec un conseiller : on cadre ton projet/.test(m.text) && /avec les plans et les prix réels\.$/.test(m.text), "le texte est celui validé");
ok(!/https?:/.test(m.text), "aucune adresse écrite dans le texte");
ok(m.text.length <= 640, "640 caractères au plus (limite d'Instagram pour un message à bouton) : " + m.text.length);
ok(m.boutons.length === 1 && m.boutons[0].title === "Voir le planning" && m.boutons[0].url === LIEN_PLANNING, "un bouton « Voir le planning »");
ok(m.boutons.every((b) => b.title.length <= 20), "bouton de 20 caractères au plus");
ok(LIEN_PLANNING === "https://www.glrimmobilier.com/rdv/?v=theophile&f=appel", "le bouton ouvre le planning de Théophile, sur l'appel");
ok(new TextEncoder().encode(enTexte(m)).length <= 1000 && enTexte(m).endsWith("Voir le planning : " + LIEN_PLANNING), "repli en texte : adresse écrite, 1000 octets au plus");

let r = demarrerDepuisCommentaire("camille_93");
ok(r.conv.etape === "planning" && r.conv.reponses.pseudo === "camille_93" && r.messages.length === 1 && r.messages[0].text === TEXTE_RDV, "commentaire : un seul message, le bon");

r = repondre(null, "Bonjour, j'ai une question sur un programme", null);
ok(r.conv === null && r.messages.length === 0, "message privé qui ne parle pas de plans : le robot se tait");
r = repondre(null, "plans svp", null);
ok(r.conv.etape === "planning" && r.messages.length === 1 && r.messages[0].text === TEXTE_RDV, "message privé « plans » : le même message");
const apres = r.conv;
r = repondre(apres, "merci !", null);
ok(r.messages.length === 0 && r.conv === apres, "après le message : le robot se tait, un humain répond");
r = repondre(apres, "PLAN", null);
ok(r.messages.length === 1 && r.messages[0].text === TEXTE_RDV, "la personne redemande « plan » : le message repart");

r = repondre(apres, "STOP", null);
ok(r.conv.etape === "refus" && r.messages.length === 1 && r.messages[0].text === "C'est noté, je m'arrête là.", "STOP : le robot s'arrête");
const refus = r.conv;
r = repondre(refus, "stop", null);
ok(r.messages.length === 0, "STOP une deuxième fois : plus rien");
r = repondre(refus, "bonjour", null);
ok(r.messages.length === 0, "après STOP : le robot reste muet");
r = repondre(null, "stop", null);
ok(r.conv.etape === "refus" && r.messages.length === 1, "STOP sans conversation : noté");

// Conversations de l'ancien questionnaire encore en route
for (const etape of ["zone", "typologie", "budget", "coordonnees", "prenom", "telephone", "email"]) {
  r = repondre({ etape, reponses: { pseudo: "x", zone: "Pantin" }, essais: 0 }, "Pantin", null);
  ok(r.conv.etape === "planning" && r.messages[0].text === TEXTE_RDV && !r.conv.reponses.zone && r.conv.reponses.pseudo === "x", `ancien questionnaire (${etape}) : le message, et les réponses ne sont plus gardées`);
}
r = repondre({ etape: "intro", reponses: {}, essais: 0 }, "Non merci", "PLANS_NON");
ok(r.conv.etape === "ferme" && /Pas de souci/.test(r.messages[0].text), "ancienne invitation refusée : pas de message de rendez-vous");
r = repondre({ etape: "intro", reponses: {}, essais: 0 }, "", "PLANS_OUI");
ok(r.conv.etape === "planning" && r.messages[0].text === TEXTE_RDV, "ancienne invitation acceptée : le message");

// ---- 2. La fonction entière, avec une base et un Instagram simulés ----
const src = readFileSync(join(DOSSIER, "index.ts"), "utf8");
ok(!/\\u[0-9a-fA-F]{4}/.test(src + readFileSync(join(DOSSIER, "parcours.ts"), "utf8")), "aucune séquence \\u dans le source");
ok(!/\/replies/.test(src) && !/lead-inbound/.test(src.replace(/^\s*\/\/.*$/gm, "")), "aucune réponse publique, aucune création de fiche");

const SECRET = "secret-de-test";
const HARNAIS = `
const BASE = { evenements: new Map(), conversations: new Map() };
const APPELS = [];
const REGLE = { refuserBoutons: false, refuserTout: false };
globalThis.__T = { BASE, APPELS, REGLE };
globalThis.Deno = { env: { get: () => "x" }, serve: (h) => { globalThis.HANDLER = h; } };
function createClient() {
  return { from(table) {
    const f = { eq: {}, op: null, corps: null };
    const q = {
      select() { return q; }, in() { return Promise.resolve({ data: [
        { name: "ig_app_secret", value: "${SECRET}", updated_at: new Date().toISOString() },
        { name: "ig_verify_token", value: "verif", updated_at: new Date().toISOString() },
        { name: "ig_access_token", value: "EAAtest", updated_at: new Date().toISOString() } ] }); },
      eq(c, v) { f.eq[c] = v; if (f.op === "update") { const e = BASE.evenements.get(v); if (e) Object.assign(e, f.corps); return Promise.resolve({ error: null }); } return q; },
      maybeSingle() { return Promise.resolve({ data: BASE.conversations.get(f.eq.ig_user) || null }); },
      insert(ligne) { if (table !== "qdn_instagram_evenements") throw new Error("insert " + table);
        if (BASE.evenements.has(ligne.id)) return Promise.resolve({ error: { message: "doublon" } });
        BASE.evenements.set(ligne.id, { ...ligne }); return Promise.resolve({ error: null }); },
      update(corps) { f.op = "update"; f.corps = corps; return q; },
      upsert(ligne) { BASE.conversations.set(ligne.ig_user, { ...(BASE.conversations.get(ligne.ig_user) || {}), ...ligne }); return Promise.resolve({ error: null }); },
      delete() { const d = { lt() { return Promise.resolve({}); }, not() { return d; } }; return d; },
    };
    return q;
  } };
}
globalThis.fetch = async (url, opts) => {
  const corps = JSON.parse(opts.body);
  APPELS.push({ url: String(url), corps });
  const bouton = !!corps.message.attachment;
  const refus = REGLE.refuserTout || (REGLE.refuserBoutons && bouton);
  return { ok: !refus, status: refus ? 400 : 200, json: async () => (refus ? { error: { message: "refus simulé" } } : { message_id: "m" }) };
};
`;
const dir = mkdtempSync(join(tmpdir(), "qdn-"));
copyFileSync(join(DOSSIER, "parcours.ts"), join(dir, "parcours.ts"));
writeFileSync(join(dir, "index.ts"), HARNAIS + src.replace('import { createClient } from "npm:@supabase/supabase-js@2";', ""));
Math.random = () => 0.9; // pas de ménage pendant le test
await import(pathToFileURL(join(dir, "index.ts")).href);
const { BASE, APPELS, REGLE } = globalThis.__T;

let n = 0;
const envoi = async (entree, signe = true) => {
  const brut = JSON.stringify({ object: "instagram", entry: [{ id: "COMPTE", ...entree }] });
  const sig = "sha256=" + createHmac("sha256", SECRET).update(brut).digest("hex");
  APPELS.length = 0;
  const rep = await globalThis.HANDLER(new Request("https://x/functions/v1/qdn-instagram", { method: "POST", body: brut, headers: signe ? { "x-hub-signature-256": sig } : {} }));
  return rep.status;
};
const commentaire = (id, de, texte) => ({ changes: [{ field: "comments", value: { id, text: texte, from: { id: de, username: "pseudo_" + de }, media: { id: "MEDIA" } } }] });
const prive = (de, texte) => ({ messaging: [{ sender: { id: de }, message: { mid: "mid" + (++n), text: texte } }] });

ok(await envoi(commentaire("c0", "u0", "plan"), false) === 401 && APPELS.length === 0, "appel non signé : refusé, rien n'est envoyé");

ok(await envoi(commentaire("c1", "u1", "PLANS")) === 200, "commentaire « PLANS » : accepté");
ok(APPELS.length === 1 && APPELS[0].url.endsWith("/COMPTE/messages") && APPELS[0].corps.recipient.comment_id === "c1", "un seul envoi, en réponse privée au commentaire");
const p = APPELS[0]?.corps.message.attachment?.payload;
ok(p && p.template_type === "button" && p.text === TEXTE_RDV && p.buttons.length === 1 && p.buttons[0].type === "web_url" && p.buttons[0].title === "Voir le planning" && p.buttons[0].url === LIEN_PLANNING, "le message part avec son bouton vers le planning");
ok(!APPELS.some((a) => /replies/.test(a.url)), "aucune réponse publique");
ok(BASE.conversations.get("u1")?.etape === "planning" && BASE.evenements.get("c1")?.repondu === true && BASE.evenements.get("c1")?.resultat.prive.forme === "boutons", "noté : message envoyé avec bouton");

await envoi(commentaire("c1", "u1", "PLANS"));
ok(APPELS.length === 0, "le même commentaire reçu deux fois : un seul message");
await envoi(commentaire("c2", "u2", "Super programme !"));
ok(APPELS.length === 0, "commentaire sans « plan » : rien");
await envoi(commentaire("c3", "COMPTE", "plans"));
ok(APPELS.length === 0, "notre propre commentaire : rien");

REGLE.refuserBoutons = true;
await envoi(commentaire("c4", "u4", "plan"));
ok(APPELS.length === 2 && APPELS[1].corps.message.text === enTexte(M.rdv()) && APPELS[1].corps.recipient.comment_id === "c4", "bouton refusé par Instagram : le texte repart avec l'adresse du planning");
ok(BASE.evenements.get("c4")?.repondu === true && BASE.evenements.get("c4")?.resultat.prive.forme === "texte avec adresses", "noté : parti en texte");
REGLE.refuserBoutons = false;

REGLE.refuserTout = true;
await envoi(commentaire("c5", "u5", "plan"));
ok(BASE.evenements.get("c5")?.repondu === false && !BASE.conversations.has("u5"), "Instagram refuse tout : noté comme non répondu, aucune conversation gardée");
REGLE.refuserTout = false;

await envoi(prive("u6", "Bonjour, c'est quoi le prix du T3 ?"));
ok(APPELS.length === 0 && !BASE.conversations.has("u6"), "message privé sans « plan » : le robot se tait, rien n'est gardé");
await envoi(prive("u6", "je veux les plans"));
ok(APPELS.length === 1 && APPELS[0].corps.recipient.id === "u6" && APPELS[0].corps.message.attachment.payload.text === TEXTE_RDV, "message privé « plans » : le message avec bouton");
await envoi(prive("u6", "merci"));
ok(APPELS.length === 0, "ensuite : le robot se tait");
await envoi(prive("u1", "STOP"));
ok(APPELS.length === 1 && APPELS[0].corps.message.text === "C'est noté, je m'arrête là." && BASE.conversations.get("u1").etape === "refus", "STOP en message privé : arrêt");
await envoi(prive("u1", "ok"));
ok(APPELS.length === 0, "après STOP : silence");
await envoi({ messaging: [{ sender: { id: "COMPTE" }, message: { mid: "echo1", text: "plans", is_echo: true } }] });
ok(APPELS.length === 0, "nos propres messages : ignorés");
ok(![...BASE.evenements.values()].some((e) => e.type === "message" && e.texte), "le texte des messages privés n'est jamais gardé");

console.log(echecs ? `\n${echecs} échec(s)` : "\nRobot Instagram : tout est bon");
process.exit(echecs ? 1 : 0);
