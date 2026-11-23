// ---- Le vendeur est prévenu dès qu'un client prend rendez-vous --------------
//
// Jusqu'ici tous les mails du CRM partaient vers le client : un vendeur ne
// découvrait un rendez-vous qu'en ouvrant son dashboard. Cette fonction est
// l'inverse : elle écrit AU VENDEUR, sur son adresse pro, dès qu'un créneau
// bascule chez lui.
//
// Elle n'est jamais appelée par le dashboard ni par une page client : c'est le
// déclencheur `trg_creneaux_alerte_vendeur` (base) qui l'appelle, via pg_net,
// à chaque fois qu'un créneau change d'état. Deux situations, exactement :
//   · reserve               : le client vient de réserver un créneau — depuis son
//                             lien personnel, depuis le lien public d'un vendeur,
//                             ou depuis sa feuille de sélection. Peu importe la
//                             porte : le créneau passe de « libre » à « réservé ».
//                             Le mail porte alors un bouton « Confirmer le
//                             rendez-vous » (jeton à usage unique, fonction
//                             rdv-valider) : le vendeur valide sans se connecter.
//   · proposition_acceptee  : après un report, le client retient l'un des créneaux
//                             que le vendeur lui avait proposés (« proposé » →
//                             « confirmé »). Rien à valider : c'est déjà confirmé.
//                             Dans ce cas le client, lui, ne recevait rien : on
//                             lui envoie aussi sa confirmation (rdv-notif).
//
// Un rendez-vous que le vendeur fixe lui-même depuis la fiche n'envoie rien :
// il est créé directement « confirmé », le déclencheur ne le voit pas passer.
//
// Sécurité : la fonction est publique (le déclencheur n'a pas de session), mais
// elle exige l'en-tête `x-alerte-cle`, dont la valeur vit dans la table
// reglages_technique — lisible par le service_role seul, des deux côtés.
//
// Sans BREVO_API_KEY, la fonction répond « sans_cle » et rien ne casse : le
// rendez-vous est pris, il manque seulement le mail.
//
// v3 (23/11/2026) : charte GLR unique figée par Alex (« A, bleu du logo ») — couleurs
// seulement. Et plus aucune séquence d'échappement unicode dans le source : les trois
// caractères concernés sont écrits par leur code, comme dans rdv-notif (le déploiement
// décodait ces séquences).

import { createClient } from "npm:@supabase/supabase-js@2";

const LOGO = "https://alexandregrillault.github.io/glrimmobilier/logo-glr.png";
// Le dashboard ouvre directement la fiche du client avec ?fiche=<id>
const DASHBOARD = "https://alexandregrillault.github.io/glrimmobilier/index.html";
const EXPEDITEUR_DEFAUT = "contact@glrimmobilier.com";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPA_URL, SERVICE);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-alerte-cle",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// Caractères écrits par leur code pour ne jamais dépendre d'une séquence d'échappement
const ESPACE_FINE = String.fromCharCode(0x202f);
const ESPACE_INSECABLE = String.fromCharCode(0xa0);
const DIACRITIQUES = new RegExp("[" + String.fromCharCode(0x300) + "-" + String.fromCharCode(0x36f) + "]", "g");

const sansAccent = (s: unknown) =>
  String(s || "").normalize("NFD").replace(DIACRITIQUES, "").toLowerCase().trim();

function esc(s: unknown): string {
  return String(s == null ? "" : s)
    .split(ESPACE_FINE).join(ESPACE_INSECABLE)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

const MODES: Record<string, string> = { telephone: "Appel", visio: "Visio" };
const MODES_LONG: Record<string, string> = { telephone: "par téléphone", visio: "en visio" };

function jourLong(d: string): string {
  const s = new Date(d).toLocaleDateString("fr-FR", {
    weekday: "long", day: "numeric", month: "long", timeZone: "Europe/Paris"
  });
  return s.charAt(0).toUpperCase() + s.slice(1);
}
const heure = (d: string) =>
  new Date(d).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Paris" });

function dureeMin(debut: string, fin: string): number | null {
  if (!debut || !fin) return null;
  const m = Math.round((new Date(fin).getTime() - new Date(debut).getTime()) / 60000);
  return m > 0 && m <= 240 ? m : null;
}

const visioPropre = (v: unknown) => { const u = String(v || "").trim(); return /^https?:\/\/\S+$/.test(u) ? u : ""; };
const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;

// Un bouton du mail = un jeton à usage unique (table rdv_actions), pour que le
// vendeur confirme sans se connecter. La page de validation vit dans la fonction
// rdv-valider ; son adresse est un réglage, pas une constante du code.
async function lienValidation(creneauId: string, vendeur: string): Promise<string> {
  try {
    const { data: reg } = await supabase.from("reglages_technique").select("valeur").eq("cle", "valider_url").maybeSingle();
    const base = String((reg && reg.valeur) || "").trim();
    if (!base) return "";
    const o = new Uint8Array(16);
    crypto.getRandomValues(o);
    const jeton = Array.from(o).map((b) => b.toString(16).padStart(2, "0")).join("");
    const { error } = await supabase.from("rdv_actions").insert({ jeton, creneau_id: creneauId, action: "confirmer", vendeur });
    if (error) return "";
    return base + "?t=" + jeton;
  } catch (_) { return ""; }
}

// Le vendeur, tel que sa fiche le décrit : adresse pro, nom complet, salle de visio
async function ficheVendeur(vendeur: string) {
  const cible = sansAccent(vendeur);
  try {
    const { data } = await supabase.from("dashboard_data").select("vendeurs").eq("id", "main").maybeSingle();
    const liste: any[] = Array.isArray(data && data.vendeurs) ? data.vendeurs : [];
    const v = liste.find((x: any) => sansAccent(x && x.prenom) === cible);
    const mail = String((v && v.email) || "").trim().toLowerCase();
    const prenom = (v && v.prenom) || vendeur;
    const nomComplet = [prenom, (v && v.nom) || ""].map((x: unknown) => String(x || "").trim()).filter(Boolean).join(" ");
    return {
      email: /@glrimmobilier\.com$/.test(mail) ? mail : "",
      prenom, nomComplet, visio: visioPropre(v && v.visio)
    };
  } catch (_) {
    return { email: "", prenom: vendeur, nomComplet: vendeur, visio: "" };
  }
}

// Le rendez-vous dans l'agenda du vendeur : c'est lui qui fait sonner le
// téléphone le jour venu, sans que personne n'ouvre le dashboard.
function ics(o: { debut: string; fin: string; client: string; mode: string; uid: string; visio?: string; details: string }): string {
  const z = (d: string) => new Date(d).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const q = (s: string) => String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
  const titre = `${MODES[o.mode] || "Rendez-vous"} — ${o.client || "client GLR"}`;
  const desc = o.details + (o.visio ? `\nRejoindre la visio : ${o.visio}` : "");
  const lignes = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//GLR Immobilier//Rendez-vous//FR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${o.uid}-vendeur@glrimmobilier.com`,
    `DTSTAMP:${z(new Date().toISOString())}`,
    `DTSTART:${z(o.debut)}`,
    `DTEND:${z(o.fin || o.debut)}`,
    `SUMMARY:${q(titre)}`,
    `DESCRIPTION:${q(desc)}`
  ];
  if (o.visio) { lignes.push(`LOCATION:${q(o.visio)}`); lignes.push(`URL:${o.visio}`); }
  lignes.push("BEGIN:VALARM", "TRIGGER:-PT10M", "ACTION:DISPLAY", `DESCRIPTION:${q(titre)}`, "END:VALARM");
  lignes.push("END:VEVENT", "END:VCALENDAR");
  return lignes.join("\r\n");
}

// Mail interne : court, lisible sur un téléphone, aux couleurs de la maison.
function gabarit(o: { titre: string; sousTitre: string; encart: string; client: string; lien: string; bouton: string; lien2?: string; bouton2?: string }): string {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light"><style>:root{color-scheme:light only;supported-color-schemes:light}</style></head>
<body bgcolor="#f4f0e8" style="margin:0;padding:0;background:#f4f0e8;font-family:'Helvetica Neue',Arial,sans-serif;color:#161a1e">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#f4f0e8" style="background:#f4f0e8;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="520" cellpadding="0" cellspacing="0" bgcolor="#fbf8f1" style="width:100%;max-width:520px;background:#fbf8f1;border:1px solid #d8d2c5;border-radius:18px;overflow:hidden">

  <tr><td align="center" style="padding:22px 28px 4px">
    <img src="${LOGO}" alt="GLR Immobilier" width="92" style="display:block;height:auto;border:0">
    <div style="width:44px;height:2px;background:#b0894c;margin:12px auto 0"></div>
  </td></tr>

  <tr><td align="center" style="padding:16px 28px 0">
    <div style="font-size:10px;letter-spacing:1.4px;text-transform:uppercase;font-weight:700;color:#8a6a2f">${esc(o.titre)}</div>
    <div style="font-family:Georgia,serif;font-size:20px;font-weight:600;margin-top:6px">${esc(o.sousTitre)}</div>
  </td></tr>

  <tr><td style="padding:18px 28px 0">${o.encart}</td></tr>

  <tr><td style="padding:14px 28px 0">${o.client}</td></tr>

  <tr><td align="center" style="padding:20px 28px 0">
    <a href="${o.lien}" style="display:inline-block;background:#005875;color:#ffffff;text-decoration:none;font-size:15px;font-weight:700;padding:14px 30px;border-radius:12px">${esc(o.bouton)}</a>
  </td></tr>

  ${o.lien2 ? `<tr><td align="center" style="padding:12px 28px 0;font-size:13px">
    <a href="${o.lien2}" style="color:#005875;text-decoration:underline">${esc(o.bouton2 || "Ouvrir la fiche")}</a>
  </td></tr>` : ""}

  <tr><td style="padding:22px 28px 26px">
    <div style="border-top:1px solid #d8d2c5;padding-top:14px;font-size:12px;color:#616b75">
      Message automatique du CRM GLR Immobilier — pour répondre au client, réponds simplement à ce mail.
    </div>
  </td></tr>

</table>
</td></tr></table></body></html>`;
}

function encartQuand(debut: string, fin: string, mode: string, visio: string): string {
  const d = dureeMin(debut, fin);
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border:1px solid #b0894c;border-radius:14px">
    <tr><td align="center" style="padding:16px 20px">
      <div style="font-family:Georgia,serif;font-size:19px;font-weight:700;color:#161a1e">${esc(jourLong(debut))}</div>
      <div style="font-family:Georgia,serif;font-size:26px;font-weight:700;color:#005875;margin-top:2px">${esc(heure(debut))}</div>
      <div style="font-size:13px;color:#616b75;margin-top:6px">${esc(MODES[mode] || "Rendez-vous")}${d ? " · " + d + " min" : ""}</div>
      ${visio ? `<div style="font-size:12.5px;margin-top:10px;word-break:break-all"><a href="${visio}" style="color:#005875;text-decoration:underline">Rejoindre la visio</a></div>` : ""}
    </td></tr></table>`;
}

function ligne(libelle: string, valeur: string, lien?: string): string {
  if (!valeur) return "";
  const v = lien ? `<a href="${lien}" style="color:#005875;text-decoration:none">${esc(valeur)}</a>` : esc(valeur);
  return `<tr><td style="padding:7px 16px;border-bottom:1px solid #d8d2c5;font-size:14px;color:#161a1e">
      <span style="display:inline-block;min-width:74px;font-size:11px;letter-spacing:.6px;text-transform:uppercase;color:#616b75">${esc(libelle)}</span>
      <strong style="color:#161a1e;font-weight:600">${v}</strong>
    </td></tr>`;
}

function encartClient(c: any, message: string): string {
  const nom = String(c.nom || [c.prenom, c.nom_famille].filter(Boolean).join(" ") || "").trim();
  const tel = String(c.telephone || "").trim();
  const mail = String(c.email || "").trim();
  const projet = String(message || c.message || "").replace(/\s+/g, " ").trim().slice(0, 220);
  const bien = [c.typologie, c.lieu].map((x: unknown) => String(x || "").trim()).filter(Boolean).join(" · ");
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border:1px solid #d8d2c5;border-radius:14px">
    <tr><td style="padding:12px 16px 4px;font-size:10px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#8a6a2f">Le client</td></tr>
    ${ligne("Nom", nom || "Nom à confirmer")}
    ${ligne("Téléphone", tel, tel ? "tel:" + tel.replace(/\s/g, "") : undefined)}
    ${ligne("Email", mail, mail ? "mailto:" + mail : undefined)}
    ${ligne("Recherche", bien)}
    ${ligne("Source", String(c.source || "").trim())}
    ${projet ? `<tr><td style="padding:9px 16px;font-size:13.5px;color:#161a1e;font-style:italic">« ${esc(projet)} »</td></tr>` : ""}
  </table>`;
}

// Le client reçoit sa confirmation par le circuit habituel (rdv-notif), pour que
// le mail soit exactement celui des autres rendez-vous : agenda joint, lien de visio.
async function confirmerAuClient(token: string, debut: string, fin: string, mode: string, lieu: string) {
  if (!token) return;
  try {
    await fetch(SUPA_URL + "/functions/v1/rdv-notif", {
      method: "POST",
      headers: { "Authorization": "Bearer " + SERVICE, "Content-Type": "application/json" },
      body: JSON.stringify({ token, type: "confirme", debut, fin, mode, visio: visioPropre(lieu) })
    });
  } catch (e) { console.error("confirmation client", String(e)); }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch (_) { return json({ ok: false, error: "invalid_json" }, 400); }

  // Clé partagée avec le déclencheur (table reglages_technique, service_role seul)
  const { data: reg } = await supabase.from("reglages_technique").select("valeur").eq("cle", "alerte_cle").maybeSingle();
  const attendue = String((reg && reg.valeur) || "");
  if (!attendue || req.headers.get("x-alerte-cle") !== attendue) return json({ ok: false, error: "non_autorise" }, 401);

  const id = String(body.creneau || "");
  const evenement = String(body.evenement || "reserve");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ ok: false, error: "creneau_invalide" }, 400);

  const { data: c } = await supabase.from("creneaux")
    .select("id, vendeur, debut, fin, mode, lieu, statut, contact_id, selection_token, client_nom, client_message")
    .eq("id", id).maybeSingle();
  if (!c) return json({ ok: false, error: "creneau_inconnu" }, 404);
  if (!c.contact_id) return json({ ok: true, ignore: "sans_client" });

  const { data: contact } = await supabase.from("contacts")
    .select("id, nom, prenom, nom_famille, email, telephone, source, lieu, typologie, message, vendeur")
    .eq("id", c.contact_id).maybeSingle();
  if (!contact) return json({ ok: true, ignore: "fiche_absente" });

  const vendeur = String(c.vendeur || contact.vendeur || "").trim();
  const exp = await ficheVendeur(vendeur);

  // Le client, lui, attend sa confirmation quand il a retenu un créneau proposé
  if (evenement === "proposition_acceptee") {
    await confirmerAuClient(String(c.selection_token || ""), c.debut, c.fin, String(c.mode || ""), String(c.lieu || ""));
  }

  if (!exp.email) return json({ ok: false, error: "vendeur_sans_adresse", vendeur });
  const cle = Deno.env.get("BREVO_API_KEY");
  if (!cle) return json({ ok: false, error: "sans_cle" });

  const nomClient = String(contact.nom || [contact.prenom, contact.nom_famille].filter(Boolean).join(" ") || c.client_nom || "").trim();
  const mode = String(c.mode || "telephone");
  const visio = mode === "visio" ? (visioPropre(c.lieu) || exp.visio) : "";
  const d = dureeMin(c.debut, c.fin);

  const sujet = `${MODES[mode] || "Rendez-vous"} ${jourLong(c.debut).toLowerCase()} à ${heure(c.debut)}`
    + (nomClient ? ` — ${nomClient}` : "");
  const lienFiche = DASHBOARD + "?fiche=" + encodeURIComponent(contact.id);
  // Le créneau attend encore d'être validé : le vendeur peut le faire depuis le mail
  const validation = (evenement === "reserve" && c.statut === "reserve") ? await lienValidation(c.id, vendeur) : "";

  const contenu = gabarit({
    titre: evenement === "proposition_acceptee" ? "Créneau retenu par le client"
      : (validation ? "Nouveau rendez-vous — à confirmer" : "Nouveau rendez-vous"),
    sousTitre: nomClient ? `${nomClient} a réservé` : "Un client a réservé",
    encart: encartQuand(c.debut, c.fin, mode, visio),
    client: encartClient(contact, String(c.client_message || "")),
    lien: validation || lienFiche,
    bouton: validation ? "Confirmer le rendez-vous" : "Ouvrir la fiche",
    lien2: validation ? lienFiche : "",
    bouton2: "Ouvrir la fiche"
  });

  const details = [
    `${MODES[mode] || "Rendez-vous"} ${MODES_LONG[mode] || ""}${d ? " (" + d + " min)" : ""} avec ${nomClient || "un client"}.`,
    contact.telephone ? `Téléphone : ${contact.telephone}` : "",
    contact.email ? `Email : ${contact.email}` : "",
    String(c.client_message || contact.message || "").trim() ? `Demande : ${String(c.client_message || contact.message).trim().slice(0, 220)}` : "",
    `Fiche : ${lienFiche}`
  ].filter(Boolean).join("\n");

  const texte = `${sujet}\n\n${details}`
    + (validation ? `\n\nConfirmer le rendez-vous : ${validation}` : "");

  const piecesJointes: any[] = [];
  try {
    const contenuIcs = ics({ debut: c.debut, fin: c.fin, client: nomClient, mode, uid: c.id, visio, details });
    piecesJointes.push({ name: "rendez-vous.ics", content: btoa(unescape(encodeURIComponent(contenuIcs))) });
  } catch (_) { /* le mail part même sans l'agenda */ }

  const mailClient = String(contact.email || "").trim();
  try {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": cle, "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({
        sender: { name: "CRM GLR Immobilier", email: exp.email },
        // Répondre au mail, c'est écrire au client : le vendeur n'a rien à recopier
        replyTo: RE_EMAIL.test(mailClient) ? { name: nomClient || undefined, email: mailClient } : { email: exp.email },
        to: [{ email: exp.email, name: exp.nomComplet }],
        subject: sujet,
        htmlContent: contenu,
        textContent: texte,
        attachment: piecesJointes.length ? piecesJointes : undefined,
        tags: ["rdv-vendeur"]
      })
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      console.error("brevo", r.status, detail.slice(0, 300));
      return json({ ok: false, error: "envoi_refuse" });
    }
  } catch (e) {
    console.error("rdv-alerte", String(e));
    return json({ ok: false, error: "erreur" });
  }

  return json({ ok: true, vendeur: exp.email, evenement, validation: validation ? true : false });
});
