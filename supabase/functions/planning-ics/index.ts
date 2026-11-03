// ---- Le planning du vendeur dans l'app Calendrier de son téléphone ----------
//
// Demande d'Alex du 03/11/2026 : chaque commercial s'abonne une fois, depuis le
// bouton « Sur mon téléphone » de « Mon planning ». Le téléphone relit ensuite
// cette adresse tout seul (iPhone : toutes les 15 min à 1 h, à son rythme) et
// affiche le planning comme un calendrier à part, en lecture seule. Tout se crée
// et se change toujours dans le CRM.
//
// Ce qui part sur le téléphone : les rendez-vous clients (confirmés, à valider,
// proposés), les rappels calés dans le planning et le temps bloqué (activités
// perso). Jamais les créneaux libres. Nom du client et lien vers sa fiche, pas
// son téléphone ni son mail.
//
// Sécurité : l'adresse est publique (un téléphone n'a pas de session), la clé
// secrète `?cle=` en est l'autorisation. Elle vit dans `planning_abonnements`,
// lisible par le service_role seul ; le vendeur la renouvelle depuis le CRM
// (RPC `planning_abonnement_cle(true)`), et l'ancien lien cesse de marcher.

import { createClient } from "npm:@supabase/supabase-js@2";

const DASHBOARD = "https://alexandregrillault.github.io/glrimmobilier/index.html";
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Fenêtre envoyée au téléphone : un mois en arrière, quatre mois devant
const PASSE_J = 30;
const FUTUR_J = 120;

const MODES: Record<string, string> = { telephone: "Appel", visio: "Visio" };
const CATS: Record<string, string> = {
  appel: "Appels / relances", rdv: "Rendez-vous client", visite: "Visite / terrain",
  prospection: "Prospection", reunion: "Réunion interne", formation: "Formation",
  deplacement: "Déplacement", admin: "Administratif", indispo: "Indisponible"
};

const texte = (corps: string, s = 200) =>
  new Response(corps, { status: s, headers: { "Content-Type": "text/plain; charset=utf-8" } });

const z = (d: string) => new Date(d).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const q = (s: unknown) => String(s == null ? "" : s)
  .replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const visioPropre = (v: unknown) => { const u = String(v || "").trim(); return /^https?:\/\/\S+$/.test(u) ? u : ""; };

// Une ligne du format calendrier ne dépasse pas 75 octets : au-delà, on la
// replie (retour à la ligne + espace), sans couper un caractère accentué.
function plier(ligne: string): string {
  const enc = new TextEncoder();
  if (enc.encode(ligne).length <= 75) return ligne;
  const morceaux: string[] = [];
  let cur = "", taille = 0, max = 75;
  for (const ch of ligne) {
    const n = enc.encode(ch).length;
    if (taille + n > max) { morceaux.push(cur); cur = ""; taille = 0; max = 74; }
    cur += ch; taille += n;
  }
  morceaux.push(cur);
  return morceaux.join("\r\n ");
}

function evenement(c: any): string[] {
  const perso = c.origine === "perso";
  const rappel = c.origine === "rappel";
  const nom = String(c.client_nom || "").trim();
  const mode = String(c.mode || "");
  let titre: string;
  if (perso) titre = String(c.titre || CATS[c.categorie] || c.categorie || "Activité").trim();
  else if (rappel) titre = String(c.titre || "").trim() || ("Rappeler " + (nom || "un client"));
  else titre = (MODES[mode] || "Rendez-vous") + " — " + (nom || "client GLR");
  if (c.statut === "reserve") titre = "À valider · " + titre;
  if (c.statut === "propose") titre = "Proposé · " + titre;

  const visio = !perso && mode === "visio" ? visioPropre(c.lieu) : "";
  const fiche = c.contact_id ? DASHBOARD + "?fiche=" + encodeURIComponent(c.contact_id) : "";
  const desc = [
    c.statut === "reserve" ? "Réservé par le client, à valider dans le CRM." : "",
    c.statut === "propose" ? "Créneau proposé au client, en attente de sa réponse." : "",
    String(c.client_message || "").trim() ? "Demande : " + String(c.client_message).trim().slice(0, 220) : "",
    visio ? "Visio : " + visio : "",
    fiche ? "Fiche : " + fiche : ""
  ].filter(Boolean).join("\n");

  const l = [
    "BEGIN:VEVENT",
    "UID:" + c.id + "-planning@glrimmobilier.com",
    "DTSTAMP:" + z(new Date().toISOString()),
    "DTSTART:" + z(c.debut),
    "DTEND:" + z(c.fin || c.debut),
    "SUMMARY:" + q(titre),
    "STATUS:" + (c.statut === "confirme" ? "CONFIRMED" : "TENTATIVE"),
    // Le temps bloqué ne doit pas rendre le vendeur « occupé » pour rien dans les autres agendas
    "TRANSP:" + (perso && c.bloquant === false ? "TRANSPARENT" : "OPAQUE")
  ];
  if (desc) l.push("DESCRIPTION:" + q(desc));
  if (visio) l.push("LOCATION:" + q(visio));
  if (fiche || visio) l.push("URL:" + (visio || fiche));
  // Une alerte 10 min avant ce qui est sûr d'avoir lieu avec un client
  if (!perso && c.statut === "confirme") {
    l.push("BEGIN:VALARM", "TRIGGER:-PT10M", "ACTION:DISPLAY", "DESCRIPTION:" + q(titre), "END:VALARM");
  }
  l.push("END:VEVENT");
  return l;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") return texte("method_not_allowed", 405);
  const cle = new URL(req.url).searchParams.get("cle") || "";
  if (!/^[0-9a-f]{48}$/.test(cle)) return texte("lien invalide", 404);

  const { data: abo } = await supabase.from("planning_abonnements").select("vendeur").eq("cle", cle).maybeSingle();
  if (!abo) return texte("lien invalide", 404);

  const depuis = new Date(Date.now() - PASSE_J * 864e5).toISOString();
  const jusqua = new Date(Date.now() + FUTUR_J * 864e5).toISOString();
  const { data: creneaux, error } = await supabase.from("creneaux")
    .select("id, debut, fin, mode, lieu, statut, contact_id, client_nom, client_message, origine, titre, categorie, bloquant")
    .eq("vendeur", abo.vendeur).neq("statut", "libre")
    .gte("debut", depuis).lte("debut", jusqua)
    .order("debut", { ascending: true }).limit(1000);
  if (error) { console.error("planning-ics", error.message); return texte("erreur", 500); }

  const lignes = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//GLR Immobilier//Planning//FR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:" + q("GLR — " + abo.vendeur),
    "X-WR-TIMEZONE:Europe/Paris",
    "REFRESH-INTERVAL;VALUE=DURATION:PT15M",
    "X-PUBLISHED-TTL:PT15M"
  ];
  for (const c of creneaux || []) lignes.push(...evenement(c));
  lignes.push("END:VCALENDAR");

  return new Response(lignes.map(plier).join("\r\n") + "\r\n", {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": "inline; filename=\"planning-glr.ics\"",
      "Cache-Control": "no-store"
    }
  });
});
