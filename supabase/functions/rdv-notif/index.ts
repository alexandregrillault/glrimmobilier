// ---- Le client est prévenu de ce que décide son conseiller ------------------
//
// Cinq moments, cinq mails, tous au nom du vendeur (Brevo, domaine
// glrimmobilier.com déjà authentifié) :
//   · confirme   : le vendeur a validé le créneau choisi — mail de confirmation
//                 avec le rendez-vous en pièce jointe (.ics) pour son agenda ;
//   · deplace    : le vendeur a changé l'horaire d'un rendez-vous (v14, 08/09/2026) —
//                 même mail que la confirmation, mais qui dit clairement que c'est
//                 un nouvel horaire ; l'agenda joint porte le même identifiant, il
//                 remplace l'ancien rendez-vous dans le calendrier du client ;
//   · propositions : le créneau ne convenait pas, le vendeur en propose d'autres ;
//   · annule     : le créneau saute sans proposition — le client doit en reprendre un ;
//   · libre      : le vendeur écrit lui-même au client depuis la fiche (objet et
//                 texte à sa main). S'il y a mis son lien de rendez-vous, le lien
//                 est retiré du texte et devient deux boutons côte à côte sous le
//                 message : « Prendre une visio » / « Prendre un appel » (v11,
//                 03/09/2026). L'envoi laisse une trace dans les notes de la fiche.
//   · selection  : la sélection de biens (v10, 03/09/2026) — le texte du vendeur
//                 (son modèle), la liste des lots et un bouton vers la page de
//                 sélection. `maj: true` pour une sélection mise à jour.
//
// Depuis le 02/09/2026 le client choisit un format (visio 30 min / appel 10 min) :
// la durée réelle du rendez-vous (fin - début) est rappelée dans le mail et l'agenda.
//
// Depuis le 03/09/2026 (v9) : pour une visio, le mail de confirmation et l'agenda
// portent le lien de la salle fixe du vendeur (fiche vendeur, champ « Lien de
// visio »). Sans salle renseignée, on prévient que le lien suivra.
// v13 (03/09/2026) : le vendeur est nommé prénom + nom partout (exp.nomComplet),
// le mail reste clair même en mode nuit, et l'espace fine des prix (U+202F)
// devient une insécable classique, que toutes les messageries affichent.
// v14 (08/09/2026) : type `deplace` ; plus aucune séquence d'échappement unicode
// dans le source (le déploiement les décodait et pouvait perdre les espaces exotiques).
// v15 (09/09/2026) : le rendez-vous arrive dans l'agenda du client comme une vraie
// invitation (METHOD:REQUEST, organisateur = le vendeur, invité = le client) — Gmail,
// Outlook et Apple Mail affichent la carte « Oui / Non / Peut-être » en tête du mail
// au lieu d'une simple pièce jointe ; et l'encart porte des liens « Ajouter à mon
// agenda » (Google Agenda, Outlook) pré-remplis, pour les messageries qui n'affichent
// pas la carte. Demande d'Alex après le test de bout en bout du 09/09/2026.
// v16 (11/09/2026) : le bouton « Rejoindre la visio » ne mène plus directement à la
// salle Google Meet mais à la page du rendez-vous (rdv/?t=…), qui porte le bouton
// d'entrée et explique quoi faire. Raison : une salle Meet de compte perso refuse
// tout le monde tant que le vendeur n'y est pas (« Vous ne pouvez pas participer à
// cet appel vidéo »), et les clients en avance croyaient le lien cassé. La salle
// reste dans l'agenda joint (LOCATION) et dans les liens « Ajouter à mon agenda ».
// v17 (01/10/2026) : le client est adressé selon le réglage posé une fois sur sa
// fiche (civilite + mode_adresse — « Monsieur Dupont », « Camille Durand » ou
// simplement son prénom) plutôt que toujours par son seul prénom, dans tous les
// mails de rendez-vous (confirme, deplace, propositions, annule). Même logique
// que la feuille sélection — demande d'Alex : toutes les communications écrites.
// v18 (02/10/2026) : le logo est servi par le site de la maison
// (www.glrimmobilier.com/logo-glr.png) et plus par github.io — délivrabilité,
// rendu identique.
// v19 (06/10/2026) : type `reponse` — le conseiller a répondu au commentaire du
// client sur un lot (fil enregistré en base par selection_repondre) ; le client
// reçoit un mail court avec la réponse et un bouton vers sa page, où il peut
// répondre à son tour.
// v20 (08/10/2026) : avis Google — sous la signature, une petite phrase cliquable
// (lien caché) invite le client à laisser un avis sur la fiche Google de GLR. Elle
// n'apparaît qu'à partir du mail de sélection : dans le mail de sélection lui-même,
// puis dans tous les mails envoyés à un client qui a déjà reçu une sélection
// (décision d'Alex, 08/10/2026). Lien et phrase dans reglages_mail
// (avis_google_url, avis_google_texte), modifiables sans redéployer.
// v21 (23/11/2026) : charte GLR unique figée par Alex (« A, bleu du logo ») — couleurs
// seulement, aucun texte ni aucune logique ne change. Boutons, liens et heure du
// rendez-vous en bleu du logo (#005875) ; filet, bordures d'encart et étoiles en laiton
// (#b0894c) ; petits titres en capitales en laiton foncé (#8a6a2f) ; fond #f4f0e8,
// texte #161a1e, texte discret #616b75, traits #d8d2c5.
//
// `apercu: true` dans le corps : la fonction renvoie le mail fabriqué (sujet + html)
// sans l'envoyer — c'est l'aperçu « tel que le client le recevra » du dashboard.
// Appelée par le dashboard (JWT du vendeur exigé). Le token vaut aussi bien pour
// une sélection que pour un lien de rendez-vous simple : on regarde les deux.
// Sans clé BREVO_API_KEY, la fonction répond « sans_cle » et rien ne casse.

import { createClient } from "npm:@supabase/supabase-js@2";

// Pages client sur le domaine GLR (dépôt glr-site) — jamais l'adresse technique dans un mail
const SEL_URL = "https://www.glrimmobilier.com/selection/?t=";
const RDV_URL = "https://www.glrimmobilier.com/rdv/?t=";
const LOGO = "https://www.glrimmobilier.com/logo-glr.png";
const SITE = "https://www.glrimmobilier.com";
const EXPEDITEUR_DEFAUT = "contact@glrimmobilier.com";

// Avis Google (v20) : filet de sécurité si reglages_mail est vide
const AVIS_URL_DEFAUT = "https://g.page/r/CW4l4LQfNxLdEBM/review";
const AVIS_TEXTE_DEFAUT = "Votre avis compte : laissez-nous un mot sur Google";

// Caractères écrits par leur code pour ne jamais dépendre d'une séquence d'échappement
const ESPACE_FINE = String.fromCharCode(0x202f);
const ESPACE_INSECABLE = String.fromCharCode(0xa0);
const DIACRITIQUES = new RegExp("[" + String.fromCharCode(0x300) + "-" + String.fromCharCode(0x36f) + "]", "g");
const ETOILES = String.fromCharCode(0x2605).repeat(5);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const sansAccent = (s: string) =>
  String(s || "").normalize("NFD").replace(DIACRITIQUES, "").toLowerCase().trim();

function esc(s: unknown): string {
  return String(s == null ? "" : s)
    .split(ESPACE_FINE).join(ESPACE_INSECABLE)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// Avis Google (v20) : lien et phrase relus dans reglages_mail à chaque envoi
async function lireAvis(): Promise<{ url: string; texte: string }> {
  let url = AVIS_URL_DEFAUT, texte = AVIS_TEXTE_DEFAUT;
  try {
    const { data } = await supabase.from("reglages_mail").select("cle, valeur").in("cle", ["avis_google_url", "avis_google_texte"]);
    (data || []).forEach((r: any) => {
      const v = String((r && r.valeur) || "").trim();
      if (!v) return;
      if (r.cle === "avis_google_url" && /^https:\/\/\S+$/.test(v)) url = v;
      if (r.cle === "avis_google_texte") texte = v;
    });
  } catch (_) { /* valeurs par défaut */ }
  return { url, texte };
}

// Le client a-t-il déjà reçu une sélection ? (une sélection enregistrée pour sa fiche)
async function aDejaUneSelection(contactId: string | null): Promise<boolean> {
  if (!contactId) return false;
  try {
    const { data } = await supabase.from("selections").select("token").eq("contact_id", contactId).limit(1);
    return Array.isArray(data) && data.length > 0;
  } catch (_) {
    return false;
  }
}

// Texte libre du vendeur → paragraphes HTML (une ligne vide sépare les
// paragraphes), les adresses web deviennent cliquables — c'est comme ça que le
// lien de rendez-vous voyage, dans le texte, là où le vendeur l'a mis.
function paragraphes(texte: string): string {
  const lier = (p: string) => esc(p).replace(/https?:\/\/[^\s<]+/g, (u) =>
    `<a href="${u}" style="color:#005875;font-weight:700;text-decoration:underline;word-break:break-all">${u}</a>`);
  return String(texte || "").replace(/\r\n?/g, "\n").trim().split(/\n{2,}/)
    .map((p) => `<p style="margin:0 0 12px">${lier(p).replace(/\n/g, "<br>")}</p>`)
    .join("");
}

const MODES: Record<string, string> = { telephone: "par téléphone", visio: "en visio" };

// Durée réelle du rendez-vous en minutes, null si on ne la connaît pas
function dureeMin(debut: string, fin: string): number | null {
  if (!debut || !fin) return null;
  const m = Math.round((new Date(fin).getTime() - new Date(debut).getTime()) / 60000);
  return m > 0 && m <= 240 ? m : null;
}

function jourLong(d: string): string {
  const s = new Date(d).toLocaleDateString("fr-FR", {
    weekday: "long", day: "numeric", month: "long", timeZone: "Europe/Paris"
  });
  return s.charAt(0).toUpperCase() + s.slice(1);
}
const heure = (d: string) =>
  new Date(d).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Paris" });

// Date en UTC compact pour les agendas : 20260909T123000Z
const dateAgenda = (d: string) => new Date(d).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");

// Une adresse de visio propre, ou vide
const visioPropre = (v: unknown) => { const u = String(v || "").trim(); return /^https?:\/\/\S+$/.test(u) ? u : ""; };

// Une adresse mail plausible, en minuscules, ou vide
const mailPropre = (v: unknown) => { const a = String(v || "").trim().toLowerCase(); return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(a) ? a : ""; };

async function expediteur(vendeur: string) {
  const cible = sansAccent(vendeur);
  try {
    const { data } = await supabase.from("dashboard_data").select("vendeurs").eq("id", "main").maybeSingle();
    const liste: any[] = Array.isArray(data && data.vendeurs) ? data.vendeurs : [];
    const v = liste.find((x: any) => sansAccent(x && x.prenom) === cible);
    const mail = String((v && v.email) || "").trim().toLowerCase();
    const prenom = (v && v.prenom) || vendeur;
    // Prénom et nom, dès la première ligne (demande d'Alex, 03/09/2026) : « Anaïs Mellan »
    const nomComplet = [prenom, (v && v.nom) || ""].map((x: unknown) => String(x || "").trim()).filter(Boolean).join(" ");
    const visio = visioPropre(v && v.visio);
    if (mail && /@glrimmobilier\.com$/.test(mail)) return { email: mail, prenom, nomComplet, visio };
    return { email: EXPEDITEUR_DEFAUT, prenom, nomComplet, visio };
  } catch (_) {
    return { email: EXPEDITEUR_DEFAUT, prenom: vendeur, nomComplet: vendeur, visio: "" };
  }
}

// Titre et description du rendez-vous, communs à l'agenda joint et aux liens
// « Ajouter à mon agenda ». `page` : la page du rendez-vous, qui porte le bouton
// d'entrée dans la visio et le mode d'emploi.
function texteAgenda(o: { vendeur: string; mode: string; debut: string; fin: string; visio?: string; page?: string }) {
  const d = dureeMin(o.debut, o.fin);
  const titre = `Rendez-vous GLR Immobilier avec ${o.vendeur}`;
  const desc = `Échange ${MODES[o.mode] || ""}${d ? " (" + d + " min)" : ""} avec ${o.vendeur}, GLR Immobilier.`
    + (o.visio && o.page ? `\nEntrer dans la visio (à l'heure du rendez-vous) : ${o.page}` : "")
    + (o.visio ? `\nSalle de visio : ${o.visio}` : "");
  return { titre, desc };
}

// Le rendez-vous dans l'agenda du client. Depuis la v15 c'est une invitation
// (METHOD:REQUEST) : le vendeur organise, le client est invité — les messageries
// affichent la carte « Oui / Non / Peut-être » et rangent le rendez-vous dans
// l'agenda. `sequence` > 0 quand c'est une nouvelle version du même rendez-vous
// (déplacé) : l'agenda remplace l'ancienne entrée au lieu d'en créer une deuxième.
function ics(o: { debut: string; fin: string; vendeur: string; mode: string; uid: string; visio?: string; page?: string; sequence?: number; organisateur?: { nom: string; email: string }; invite?: { nom: string; email: string } }): string {
  const q = (s: string) => String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
  const { titre, desc } = texteAgenda(o);
  const lignes = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//GLR Immobilier//Rendez-vous//FR",
    "CALSCALE:GREGORIAN",
    "METHOD:REQUEST",
    "BEGIN:VEVENT",
    `UID:${o.uid}@glrimmobilier.com`,
    `SEQUENCE:${o.sequence || 0}`,
    `DTSTAMP:${dateAgenda(new Date().toISOString())}`,
    `DTSTART:${dateAgenda(o.debut)}`,
    `DTEND:${dateAgenda(o.fin || o.debut)}`,
    `SUMMARY:${q(titre)}`,
    `DESCRIPTION:${q(desc)}`,
    "STATUS:CONFIRMED",
    "TRANSP:OPAQUE"
  ];
  if (o.organisateur && o.organisateur.email) lignes.push(`ORGANIZER;CN=${q(o.organisateur.nom || o.organisateur.email)}:mailto:${o.organisateur.email}`);
  if (o.invite && o.invite.email) lignes.push(`ATTENDEE;CN=${q(o.invite.nom || o.invite.email)};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${o.invite.email}`);
  // La salle reste en LOCATION (les agendas en font un bouton « Rejoindre ») ;
  // l'URL de l'événement pointe sur la page du rendez-vous, qui explique quoi faire.
  if (o.visio) { lignes.push(`LOCATION:${q(o.visio)}`); lignes.push(`URL:${o.page || o.visio}`); }
  lignes.push("END:VEVENT", "END:VCALENDAR");
  return lignes.join("\r\n");
}

// Liens « Ajouter à mon agenda » pré-remplis (Google Agenda, Outlook) — un clic
// pour les messageries qui n'affichent pas la carte d'invitation.
function liensAgenda(o: { debut: string; fin: string; vendeur: string; mode: string; visio?: string; page?: string }): { google: string; outlook: string } {
  const { titre, desc } = texteAgenda(o);
  const fin = o.fin || o.debut;
  const e = encodeURIComponent;
  const google = "https://calendar.google.com/calendar/render?action=TEMPLATE"
    + "&text=" + e(titre) + "&dates=" + dateAgenda(o.debut) + "/" + dateAgenda(fin)
    + "&details=" + e(desc) + (o.visio ? "&location=" + e(o.visio) : "");
  const outlook = "https://outlook.live.com/calendar/0/action/compose?rru=addevent"
    + "&subject=" + e(titre) + "&startdt=" + e(new Date(o.debut).toISOString()) + "&enddt=" + e(new Date(fin).toISOString())
    + "&body=" + e(desc) + (o.visio ? "&location=" + e(o.visio) : "");
  return { google, outlook };
}

// Mise en page commune. `prenom` vide = pas de ligne « Bonjour » (le vendeur l'a
// écrite lui-même) ; `titre` vide = pas de titre ; `lien` vide = pas de bouton ;
// `lien2` = second lien discret sous le bouton. Le mail reste clair même quand la
// messagerie est en mode nuit (color-scheme light + bgcolor sur les tables).
// `avis` (v20) : petite phrase cliquable vers la fiche Google, sous la signature.
function gabarit(o: { prenom: string; vendeur: string; titre: string; texte: string; encart?: string; bouton: string; lien: string; bouton2?: string; lien2?: string; formule?: string; avis?: { url: string; texte: string } | null }): string {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light"><style>:root{color-scheme:light only;supported-color-schemes:light}</style></head>
<body bgcolor="#f4f0e8" style="margin:0;padding:0;background:#f4f0e8;font-family:'Helvetica Neue',Arial,sans-serif;color:#161a1e">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#f4f0e8" style="background:#f4f0e8;padding:26px 12px">
<tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" bgcolor="#fbf8f1" style="width:100%;max-width:560px;background:#fbf8f1;border:1px solid #d8d2c5;border-radius:18px;overflow:hidden">

  <tr><td align="center" style="padding:26px 30px 6px">
    <img src="${LOGO}" alt="GLR Immobilier" width="110" style="display:block;height:auto;border:0">
    <div style="width:54px;height:2px;background:#b0894c;margin:14px auto 0"></div>
  </td></tr>

  <tr><td style="padding:20px 30px 6px">
    ${o.prenom ? `<div style="font-family:Georgia,serif;font-size:21px;font-weight:600;margin-bottom:10px">Bonjour ${esc(o.prenom)},</div>` : ""}
    ${o.titre ? `<div style="font-family:Georgia,serif;font-size:19px;font-weight:600;color:#161a1e;margin-bottom:8px">${esc(o.titre)}</div>` : ""}
    <div style="font-size:15px;line-height:1.6;color:#161a1e">${o.texte}</div>
  </td></tr>

  ${o.encart ? `<tr><td style="padding:18px 30px 0">${o.encart}</td></tr>` : ""}

  ${o.lien ? `<tr><td align="center" style="padding:22px 30px 0">
    <a href="${o.lien}" style="display:inline-block;background:#005875;color:#ffffff;text-decoration:none;font-size:16px;font-weight:700;padding:15px 34px;border-radius:12px">${esc(o.bouton)}</a>
  </td></tr>` : ""}

  ${o.lien2 ? `<tr><td align="center" style="padding:12px 30px 0;font-size:13px">
    <a href="${o.lien2}" style="color:#005875;text-decoration:underline">${esc(o.bouton2 || o.lien2)}</a>
  </td></tr>` : ""}

  <tr><td style="padding:26px 30px 30px">
    <div style="border-top:1px solid #d8d2c5;padding-top:16px;font-size:13.5px;color:#161a1e">
      ${o.formule ? esc(o.formule) + "<br>" : (o.prenom || o.titre ? "À très vite,<br>" : "")}<strong>${esc(o.vendeur)}</strong><br>
      <span style="color:#616b75">GLR Immobilier — <a href="${SITE}" style="color:#005875;text-decoration:none">glrimmobilier.com</a></span>
    </div>
    ${o.avis && o.avis.url ? `<div style="margin-top:14px;font-size:12.5px;color:#616b75"><span style="color:#b0894c;letter-spacing:1px">${ETOILES}</span>&nbsp; <a href="${o.avis.url}" style="color:#005875;text-decoration:underline">${esc(o.avis.texte)}</a></div>` : ""}
  </td></tr>

</table>
</td></tr></table></body></html>`;
}

// `agenda` : liens « Ajouter à mon agenda », affichés sous le lien de visio.
// `visio` non vide = c'est une visio : on ne montre plus l'adresse brute de la
// salle (v16) — le bouton du mail mène à la page du rendez-vous, qui explique
// comment entrer ; on le dit en une ligne.
function encartQuand(debut: string, fin: string, mode: string, visio?: string, etiquette?: string, agenda?: { google: string; outlook: string }): string {
  const d = dureeMin(debut, fin);
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border:1px solid #b0894c;border-radius:14px">
    <tr><td align="center" style="padding:18px 22px">
      <div style="font-size:10px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#8a6a2f;margin-bottom:6px">${esc(etiquette || "Votre rendez-vous")}</div>
      <div style="font-family:Georgia,serif;font-size:21px;font-weight:700;color:#161a1e">${esc(jourLong(debut))}</div>
      <div style="font-family:Georgia,serif;font-size:26px;font-weight:700;color:#005875;margin-top:2px">${esc(heure(debut))}</div>
      <div style="font-size:13px;color:#616b75;margin-top:6px">Échange ${esc(MODES[mode] || "")}${d ? " · " + d + " min" : ""}</div>
      ${visio ? `<div style="font-size:12.5px;color:#616b75;margin-top:10px">À l'heure du rendez-vous, le bouton ci-dessous vous conduit à la salle de visio, depuis un ordinateur ou un téléphone.</div>` : ""}
      ${agenda ? `<div style="font-size:12.5px;color:#616b75;margin-top:12px;padding-top:10px;border-top:1px solid #d8d2c5">Ajouter à mon agenda :
        <a href="${agenda.google}" style="color:#005875;font-weight:700;text-decoration:underline">Google Agenda</a>
        &nbsp;·&nbsp; <a href="${agenda.outlook}" style="color:#005875;font-weight:700;text-decoration:underline">Outlook</a>
        &nbsp;·&nbsp; Apple / autre : l'invitation jointe à ce mail</div>` : ""}
    </td></tr></table>`;
}

// Les biens de la sélection, en liste sobre : programme et lot, ville, surface, prix.
// Au-delà de six, on compte le reste — la page fait le travail.
function encartBiens(liste: any[]): string {
  const MAX = 6;
  const lignes = liste.slice(0, MAX).map((b: any) => {
    const typo = Array.isArray(b.typologies) ? b.typologies.join(" / ") : b.typologies;
    const details = [typo, b.ville, b.surface].map((x: unknown) => String(x || "").trim()).filter(Boolean).join(" · ");
    return `<tr><td style="padding:10px 16px;border-bottom:1px solid #d8d2c5">
       <div style="font-size:14.5px;font-weight:700;color:#161a1e">${esc(b.titre || "Bien")}</div>
       <div style="font-size:12.5px;color:#616b75;margin-top:2px">${esc(details)}${b.prix ? (details ? " · " : "") + `<strong style="color:#005875">${esc(b.prix)}</strong>` : ""}</div>
     </td></tr>`; }).join("");
  const reste = liste.length - MAX;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border:1px solid #d8d2c5;border-radius:14px">
    <tr><td style="padding:14px 16px 6px;font-size:10px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#8a6a2f">${liste.length > 1 ? liste.length + " biens sélectionnés pour vous" : "Le bien sélectionné pour vous"}</td></tr>
    ${lignes}
    ${reste > 0 ? `<tr><td style="padding:11px 16px;font-size:12.5px;color:#616b75">… et ${reste} autre${reste > 1 ? "s" : ""} sur la page.</td></tr>` : ""}
  </table>`;
}

// Deux boutons côte à côte vers les disponibilités du vendeur, le format déjà
// choisi : visio (30 min) ou appel (10 min). La page lit ?f=visio|appel.
function encartFormats(lien: string): string {
  const carte = (f: string, titre: string, sous: string) =>
    `<td width="50%" style="padding:0 6px">
       <a href="${lien}&f=${f}" style="display:block;background:#ffffff;border:2px solid #b0894c;border-radius:14px;padding:16px 10px;text-align:center;text-decoration:none">
         <div style="font-size:15px;font-weight:700;color:#161a1e">${titre}</div>
         <div style="font-size:12px;color:#616b75;margin-top:4px">${sous}</div>
       </a>
     </td>`;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td colspan="2" align="center" style="padding:0 6px 10px;font-size:10px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#8a6a2f">Choisissez votre créneau</td></tr>
    <tr>${carte("visio", "Prendre une visio", "30 min · on prend le temps de tout voir")}${carte("appel", "Prendre un appel", "10 min · un premier échange")}</tr>
  </table>`;
}

function encartCreneaux(liste: any[]): string {
  const lignes = liste.map((c: any) =>
    `<tr><td style="padding:9px 16px;border-bottom:1px solid #d8d2c5;font-size:14.5px;color:#161a1e">
       <strong style="color:#161a1e">${esc(jourLong(c.debut))}</strong> à ${esc(heure(c.debut))}
     </td></tr>`).join("");
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border:1px solid #d8d2c5;border-radius:14px">
    <tr><td style="padding:14px 16px 6px;font-size:10px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#8a6a2f">Les créneaux proposés</td></tr>
    ${lignes}
    <tr><td style="padding:11px 16px;font-size:12.5px;color:#616b75">Celui que vous retenez est confirmé immédiatement.</td></tr>
  </table>`;
}

// Trace dans les notes de la fiche : quel jour, qui, quel objet
async function tracerDansLaFiche(contactId: string | null, ligne: string) {
  if (!contactId) return;
  try {
    const { data } = await supabase.from("contacts").select("notes").eq("id", contactId).maybeSingle();
    const notes = String((data && data.notes) || "").trim();
    await supabase.from("contacts").update({ notes: notes ? notes + "\n" + ligne : ligne }).eq("id", contactId);
  } catch (_) { /* le mail est parti, c'est l'essentiel */ }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch (_) { return json({ ok: false, error: "invalid_json" }, 400); }

  const token = String(body.token || "");
  const type = String(body.type || "");
  if (!/^[a-f0-9]{6,32}$/i.test(token)) return json({ ok: false, error: "token_invalide" }, 400);
  if (!["confirme", "deplace", "propositions", "annule", "libre", "selection", "reponse"].includes(type)) return json({ ok: false, error: "type_inconnu" }, 400);

  const cle = Deno.env.get("BREVO_API_KEY");

  // Le token vient soit d'une sélection, soit d'un lien de rendez-vous simple
  let email = "", nom = "", prenom = "", vendeur = "", lien = "", contactId: string | null = null;
  let biens: any[] = [];

  const { data: sel } = await supabase.from("selections")
    .select("token, contact_id, client_nom, client_email, vendeur, biens, avis").eq("token", token).maybeSingle();

  if (sel) {
    contactId = sel.contact_id || null;
    email = String(sel.client_email || "").trim();
    nom = String(sel.client_nom || "").trim();
    vendeur = String(sel.vendeur || "").trim();
    lien = SEL_URL + token;
    biens = Array.isArray(sel.biens) ? sel.biens : [];
  } else {
    const { data: lk } = await supabase.from("rdv_liens")
      .select("token, contact_id, vendeur").eq("token", token).maybeSingle();
    if (!lk) return json({ ok: false, error: "lien_inconnu" }, 404);
    contactId = lk.contact_id || null;
    vendeur = String(lk.vendeur || "").trim();
    lien = RDV_URL + token;
  }

  // La fiche client fait foi pour l'adresse, le nom et le conseiller du moment —
  // et aussi pour la manière de s'adresser au client (civilite + mode_adresse,
  // réglée une fois sur la fiche, 01/10/2026).
  let civilite = "", modeAdresse = "", nomFamille = "";
  if (contactId) {
    const { data: c } = await supabase.from("contacts")
      .select("email, nom, prenom, nom_famille, civilite, mode_adresse, vendeur").eq("id", contactId).maybeSingle();
    if (c) {
      if (!email) email = String(c.email || "").trim();
      if (!nom) nom = String(c.nom || "").trim();
      prenom = String(c.prenom || "").trim();
      if (c.vendeur) vendeur = String(c.vendeur).trim();
      nomFamille = String(c.nom_famille || "").trim();
      civilite = String(c.civilite || "").trim();
      modeAdresse = String(c.mode_adresse || "").trim();
    }
  }
  if (!prenom && nom) prenom = nom.split(/\s+/)[0] || "";
  if (prenom && prenom === prenom.toLowerCase()) prenom = prenom.charAt(0).toUpperCase() + prenom.slice(1);

  // « Monsieur Dupont », « Camille Durand » ou simplement le prénom (comportement
  // historique, par défaut) — même logique que salutationDe() côté feuille
  // sélection, appliquée ici aux mails de rendez-vous (01/10/2026, demande
  // d'Alex : le réglage posé une fois sur la fiche vaut pour toutes les
  // communications écrites, pas seulement la sélection).
  let salutationClient = prenom;
  if (modeAdresse === "civilite_nom" && civilite && nomFamille) salutationClient = civilite + " " + nomFamille;
  else if (modeAdresse === "prenom_nom" && prenom && nomFamille) salutationClient = prenom + " " + nomFamille;

  // Avis Google (v20) : à partir du mail de sélection — le mail de sélection lui-même,
  // ou tout mail à un client qui a déjà une sélection enregistrée.
  const avisActif = type === "selection" || !!sel || await aDejaUneSelection(contactId);
  const avis = avisActif ? await lireAvis() : null;

  // apercu: true — on fabrique le mail et on le renvoie au dashboard sans l'envoyer
  // (le vendeur voit ce que le client recevra). Pas de trace, pas de clé nécessaire.
  const apercu = body.apercu === true;
  if (!email && !apercu) return json({ ok: false, error: "sans_email" });
  if (!cle && !apercu) return json({ ok: false, error: "sans_cle" });

  const exp = await expediteur(vendeur);
  let sujet = "", contenu = "", texte = "";
  const piecesJointes: any[] = [];
  let trace = "";

  // Adresse interne (@glrimmobilier.com) qui reçoit le mail À LA PLACE du client :
  // pour voir à quoi ressemble un envoi sans déranger personne. Pas de trace.
  const interne = (v: unknown) => { const a = String(v || "").trim().toLowerCase(); return /^[^@\s]+@glrimmobilier\.com$/.test(a) ? a : ""; };
  const testA = interne(body.test_a);
  // Copie cachée à une adresse interne (le vendeur qui veut garder un double)
  const copieA = interne(body.copie_a);

  if (type === "confirme" || type === "deplace") {
    const debut = String(body.debut || "");
    const fin = String(body.fin || "");
    const mode = String(body.mode || "telephone");
    if (!debut) return json({ ok: false, error: "creneau_manquant" }, 400);
    const d = dureeMin(debut, fin);
    // Lien de visio : celui passé par le dashboard (collé sur le créneau), sinon la salle fixe du vendeur
    const visio = mode === "visio" ? (visioPropre(body.visio) || exp.visio) : "";
    const deplace = type === "deplace";
    // Ancien horaire, pour que le client comprenne ce qui change
    const ancien = deplace && body.ancien_debut ? String(body.ancien_debut) : "";
    const memeJour = ancien && new Date(ancien).toLocaleDateString("fr-FR", { timeZone: "Europe/Paris" }) === new Date(debut).toLocaleDateString("fr-FR", { timeZone: "Europe/Paris" });

    sujet = deplace
      ? `Nouvel horaire pour votre rendez-vous — ${jourLong(debut).toLowerCase()} à ${heure(debut)}`
      : `Rendez-vous confirmé — ${jourLong(debut).toLowerCase()} à ${heure(debut)}`;
    // Pour une visio, le bouton mène à la page du rendez-vous (v16) : elle porte
    // le bouton d'entrée dans la salle et explique quoi faire si Google refuse
    // (le vendeur n'y est pas encore). Sans salle renseignée, le lien suivra.
    const phraseVisio = mode !== "visio" ? ""
      : visio ? " À l'heure du rendez-vous, cliquez sur le bouton ci-dessous : il vous conduit à la salle de visio, depuis un ordinateur ou un téléphone."
      : " Je vous enverrai le lien de connexion juste avant le rendez-vous.";
    const phraseAncien = !ancien ? ""
      : memeJour ? ` (au lieu de ${heure(ancien)})`
      : ` (au lieu du ${jourLong(ancien).toLowerCase()} à ${heure(ancien)})`;
    const intro = deplace
      ? `Petit changement de programme : notre rendez-vous est déplacé à ${jourLong(debut).toLowerCase()} à ${heure(debut)}${phraseAncien}. Je vous appelle ${MODES[mode] || ""} à ce moment-là${d ? ", pour environ " + d + " minutes" : ""}.${phraseVisio} Si ce nouvel horaire ne vous convient pas, répondez simplement à ce message.`
      : `C'est noté de mon côté : je vous appelle ${MODES[mode] || ""} à ce moment-là${d ? ", pour environ " + d + " minutes" : ""}.${phraseVisio} Si un imprévu se présente, répondez simplement à ce message.`;
    const agenda = liensAgenda({ debut, fin, vendeur: exp.nomComplet, mode, visio, page: visio ? lien : "" });
    contenu = gabarit({
      prenom: salutationClient, vendeur: exp.nomComplet,
      titre: deplace ? "Votre rendez-vous a été déplacé" : "Votre rendez-vous est confirmé",
      texte: esc(intro),
      encart: encartQuand(debut, fin, mode, visio, deplace ? "Votre nouveau rendez-vous" : "Votre rendez-vous", agenda),
      bouton: visio ? "Rejoindre la visio" : "Voir mon rendez-vous",
      lien, avis
    });
    texte = `Bonjour ${salutationClient},\n\n`
      + (deplace
        ? `Votre rendez-vous avec ${exp.nomComplet} est deplace : ${jourLong(debut)} a ${heure(debut)}${ancien ? " (au lieu de " + jourLong(ancien) + " a " + heure(ancien) + ")" : ""} (${MODES[mode] || ""}${d ? ", " + d + " min" : ""}).\n\n`
        : `Votre rendez-vous avec ${exp.nomComplet} est confirme : ${jourLong(debut)} a ${heure(debut)} (${MODES[mode] || ""}${d ? ", " + d + " min" : ""}).\n\n`)
      + (visio ? `Rejoindre la visio (a l'heure du rendez-vous) : ${lien}\n\n` : `Voir mon rendez-vous : ${lien}\n`)
      + `Ajouter a mon agenda (Google) : ${agenda.google}\n\nA tres vite,\n${exp.nomComplet}\nGLR Immobilier`;

    try {
      // L'invité est celui qui reçoit réellement le mail (le client, ou l'adresse
      // interne d'un envoi de test) — la messagerie n'affiche la carte que si
      // l'invitation lui est adressée. Le nom affiché dans l'invitation reste
      // prénom + nom (fiche d'identité), indépendamment du réglage de salutation.
      const destinataire = mailPropre(testA || email);
      const contenuIcs = ics({
        debut, fin, vendeur: exp.nomComplet, mode, uid: token, visio, page: visio ? lien : "",
        sequence: deplace ? Math.floor(Date.now() / 1000) : 0,
        organisateur: { nom: exp.nomComplet, email: exp.email },
        invite: destinataire ? { nom: [prenom, nom].filter(Boolean).join(" ").trim() || destinataire, email: destinataire } : undefined
      });
      piecesJointes.push({ name: "rendez-vous.ics", content: btoa(unescape(encodeURIComponent(contenuIcs))) });
    } catch (_) { /* le mail part même sans la pièce jointe */ }

  } else if (type === "propositions") {
    const creneaux: any[] = Array.isArray(body.creneaux) ? body.creneaux.filter((c: any) => c && c.debut) : [];
    sujet = `${exp.nomComplet} vous propose d'autres créneaux`;
    contenu = gabarit({
      prenom: salutationClient, vendeur: exp.nomComplet,
      titre: "Le créneau que vous aviez choisi n'était plus libre",
      texte: "Désolé pour ce contretemps. Voici d'autres moments où je suis disponible : celui que vous retenez est confirmé tout de suite, sans nouvelle validation.",
      encart: creneaux.length ? encartCreneaux(creneaux) : "",
      bouton: "Choisir un créneau",
      lien, avis
    });
    texte = `Bonjour ${salutationClient},\n\nLe creneau que vous aviez choisi n'etait plus libre. ${exp.nomComplet} vous propose d'autres moments :\n`
      + creneaux.map((c: any) => `- ${jourLong(c.debut)} a ${heure(c.debut)}`).join("\n")
      + `\n\nChoisir un creneau : ${lien}\n\nA tres vite,\n${exp.nomComplet}\nGLR Immobilier`;

  } else if (type === "libre") {
    // Le vendeur a tout écrit : objet, bonjour, texte, et le lien de rendez-vous
    // s'il le veut, à l'endroit qu'il veut. On ne rajoute que la mise en page
    // et la signature — pas de bouton à part.
    sujet = String(body.sujet || "").replace(/[\r\n]+/g, " ").trim().slice(0, 200);
    let corps = String(body.texte || "").replace(/\r\n?/g, "\n").trim().slice(0, 6000);
    const avecLien = corps.indexOf(lien) !== -1;
    if (!sujet) return json({ ok: false, error: "sujet_manquant" }, 400);
    if (!corps) return json({ ok: false, error: "texte_manquant" }, 400);
    let formule = "";
    if (avecLien) {
      // Le lien sort du texte : la ligne qui le portait disparaît si elle ne
      // disait que « Choisissez votre créneau ici : », sinon on garde la phrase.
      corps = corps.split("\n").map((l) => {
        if (l.indexOf(lien) === -1) return l;
        const reste = l.split(lien).join("").replace(/\s+/g, " ").trim();
        return (reste.length <= 60 && /[:\-–—]\s*$/.test(reste)) ? "" : reste;
      }).join("\n").replace(/\n{3,}/g, "\n\n").trim();
      // Signature et formule de politesse passent sous les boutons
      const lignes = corps.split("\n");
      while (lignes.length && /^\s*$/.test(lignes[lignes.length - 1])) lignes.pop();
      const estSignature = (l: string) => {
        const t = sansAccent(l).replace(/[^a-z ]/g, "").trim();
        return t === "glr immobilier" || t === sansAccent(exp.prenom).replace(/[^a-z ]/g, "").trim() || t === sansAccent(exp.nomComplet).replace(/[^a-z ]/g, "").trim() || t === sansAccent(vendeur).replace(/[^a-z ]/g, "").trim();
      };
      while (lignes.length && estSignature(lignes[lignes.length - 1])) lignes.pop();
      const derniere = (lignes[lignes.length - 1] || "").trim();
      if (derniere && derniere.length <= 40 && /,$/.test(derniere)) { formule = derniere; lignes.pop(); }
      corps = lignes.join("\n").trim() || corps;
    }
    contenu = gabarit({
      prenom: "", vendeur: exp.nomComplet,
      titre: "",
      texte: paragraphes(corps),
      encart: avecLien ? encartFormats(lien) : "",
      bouton: "",
      lien: "",
      formule: avecLien ? (formule || "Bien à vous,") : "",
      avis
    });
    texte = corps + (avecLien ? `\n\nPrendre une visio (30 min) : ${lien}&f=visio\nPrendre un appel (10 min) : ${lien}&f=appel\n\n${formule || "Bien a vous,"}` : "") + `\n\n${exp.nomComplet}\nGLR Immobilier`;
    const jour = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
    trace = `[${jour}] Mail envoyé par ${exp.prenom} : « ${sujet} »${avecLien ? " (avec le lien de rendez-vous)" : ""}`;

  } else if (type === "selection") {
    // Le texte est celui du modèle du vendeur. Le lien de la page devient un
    // bouton : on retire les lignes qui ne contiennent que l'adresse.
    sujet = String(body.sujet || "").replace(/[\r\n]+/g, " ").trim().slice(0, 200);
    const corps = String(body.texte || "").replace(/\r\n?/g, "\n").split("\n")
      .filter((l) => !/^\s*https?:\/\/\S+\s*$/.test(l)).join("\n")
      .replace(/https?:\/\/\S+/g, (u) => u.indexOf(lien) === 0 ? "" : u)
      .trim().slice(0, 6000);
    const maj = body.maj === true;
    if (!sujet) return json({ ok: false, error: "sujet_manquant" }, 400);
    if (!corps) return json({ ok: false, error: "texte_manquant" }, 400);
    // La signature du modèle (« Bien à vous, / Anaïs / GLR Immobilier ») est
    // reprise dans le pied du mail, sous les biens et le bouton — pas au milieu.
    const lignes = corps.split("\n");
    while (lignes.length && /^\s*$/.test(lignes[lignes.length - 1])) lignes.pop();
    const estSignature = (l: string) => {
      const t = sansAccent(l).replace(/[^a-z ]/g, "").trim();
      return t === "glr immobilier" || t === sansAccent(exp.prenom).replace(/[^a-z ]/g, "").trim() || t === sansAccent(exp.nomComplet).replace(/[^a-z ]/g, "").trim() || t === sansAccent(vendeur).replace(/[^a-z ]/g, "").trim();
    };
    while (lignes.length && estSignature(lignes[lignes.length - 1])) lignes.pop();
    let formule = "";
    const derniere = (lignes[lignes.length - 1] || "").trim();
    if (derniere && derniere.length <= 40 && /[,]$/.test(derniere)) { formule = derniere; lignes.pop(); }
    const corpsSansSignature = lignes.join("\n").trim() || corps;
    contenu = gabarit({
      prenom: "", vendeur: exp.nomComplet,
      titre: "",
      texte: paragraphes(corpsSansSignature),
      encart: biens.length ? encartBiens(biens) : "",
      bouton: maj ? "Voir ma sélection mise à jour" : "Découvrir ma sélection",
      lien,
      formule: formule || "Bien à vous,",
      avis
    });
    texte = corpsSansSignature + `\n\n${maj ? "Voir ma selection mise a jour" : "Decouvrir ma selection"} : ${lien}\n\n${formule || "Bien a vous,"}\n${exp.nomComplet}\nGLR Immobilier`;
    const jour = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
    trace = `[${jour}] ${maj ? "Mise à jour de sélection" : "Sélection"} envoyée par mail par ${exp.prenom} (${biens.length} bien${biens.length > 1 ? "s" : ""})`;

  } else if (type === "reponse") {
    // Le conseiller a répondu au commentaire du client sur un lot (fil de
    // discussion enregistré par selection_repondre, 06/10/2026) : on prévient
    // le client, qui lit la réponse et peut y répondre sur sa page.
    if (!sel) return json({ ok: false, error: "selection_inconnue" }, 404);
    const idx = Number.isInteger(body.index) ? body.index : -1;
    const avisTous = (sel.avis && typeof sel.avis === "object") ? sel.avis : {};
    const a = avisTous[String(idx)] || {};
    const fil: any[] = Array.isArray(a.fil) ? a.fil : [];
    const reponse = [...fil].reverse().find((m) => m && m.de === "conseiller");
    if (idx < 0 || !reponse || !String(reponse.texte || "").trim()) return json({ ok: false, error: "reponse_introuvable" }, 400);
    const bien = biens[idx] || {};
    const titreLot = String(bien.titre || ("Lot " + (idx + 1))).trim();
    const dernierClient = [...fil].reverse().find((m) => m && m.de === "client");
    const citation = dernierClient && String(dernierClient.texte || "").trim()
      ? `<div style="margin:0 0 14px;padding:10px 14px;border-left:3px solid #b0894c;background:#f4f0e8;border-radius:0 10px 10px 0;font-size:13.5px;color:#616b75;font-style:italic">« ${esc(String(dernierClient.texte).trim().slice(0, 600))} »</div>`
      : "";
    sujet = "Réponse de votre conseiller — " + titreLot;
    contenu = gabarit({
      prenom: salutationClient, vendeur: exp.nomComplet,
      titre: "Concernant " + titreLot,
      texte: citation + paragraphes(String(reponse.texte).trim().slice(0, 3000)),
      bouton: "Voir ma sélection et répondre",
      lien, avis
    });
    texte = `Bonjour ${salutationClient},\n\nConcernant ${titreLot}` + (dernierClient ? ` — vous m'ecriviez : « ${String(dernierClient.texte).trim().slice(0, 600)} »` : "") + `\n\n${String(reponse.texte).trim().slice(0, 3000)}\n\nVoir ma selection et repondre : ${lien}\n\nBien a vous,\n${exp.nomComplet}\nGLR Immobilier`;
    const jour = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
    trace = `[${jour}] Réponse de ${exp.prenom} au commentaire du client sur ${titreLot}, envoyée par mail`;

  } else {
    sujet = "Votre rendez-vous doit être reporté";
    contenu = gabarit({
      prenom: salutationClient, vendeur: exp.nomComplet,
      titre: "Le créneau retenu n'a pas pu être conservé",
      texte: "Désolé pour ce contretemps. Choisissez un autre moment parmi mes disponibilités, je reste à votre disposition.",
      bouton: "Choisir un autre créneau",
      lien, avis
    });
    texte = `Bonjour ${salutationClient},\n\nLe creneau retenu n'a pas pu etre conserve. Choisissez un autre moment : ${lien}\n\nA tres vite,\n${exp.nomComplet}\nGLR Immobilier`;
  }

  // Version texte : la même invitation, sous la signature (v20)
  if (avis && avis.url) texte += `\n\n${avis.texte} : ${avis.url}`;

  if (apercu) return json({ ok: true, apercu: true, sujet, html: contenu, email, piece_jointe: piecesJointes.length ? piecesJointes[0].name : null });

  try {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": cle, "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({
        sender: { name: exp.nomComplet + " — GLR Immobilier", email: exp.email },
        replyTo: { name: exp.nomComplet + " — GLR Immobilier", email: exp.email },
        to: testA ? [{ email: testA }] : [{ email, name: nom || undefined }],
        bcc: (!testA && copieA) ? [{ email: copieA }] : undefined,
        subject: (testA ? "[Copie — envoyé à " + email + "] " : "") + sujet,
        htmlContent: contenu,
        textContent: texte,
        attachment: piecesJointes.length ? piecesJointes : undefined,
        tags: ["rdv-" + type]
      })
    });
    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      console.error("brevo", r.status, detail.slice(0, 300));
      return json({ ok: false, error: "envoi_refuse" });
    }
  } catch (e) {
    console.error("rdv-notif", String(e));
    return json({ ok: false, error: "erreur" });
  }

  if (trace && !testA) await tracerDansLaFiche(contactId, trace);
  return json({ ok: true, email: testA || email });
});
