// Formulaire « plans » (www.glrimmobilier.com/plans/) -> CRM
//
// Page ouverte depuis le robot Instagram de Quoi de neuf (commentaire « PLANS »).
// Même logique que site-contact : on valide, on filtre le spam, puis on délègue
// à lead-inbound (dédoublonnage par téléphone / e-mail, fusion, paternité).
// Le jeton de lead-inbound est lu dans app_secrets, jamais écrit ici (dépôt public).
//
// Décision d'Alex du 03/11/2026 : tous ces leads arrivent chez lui d'abord.

import { createClient } from "npm:@supabase/supabase-js@2";

const VENDEUR = "alexandre";
const SOURCE = "Quoi de neuf Instagram";

const ORIGINES_AUTORISEES = [
  "https://www.glrimmobilier.com",
  "https://glrimmobilier.com",
  "https://alexandregrillault.github.io",
];

// Limite simple par IP : 3 envois par tranche de 10 minutes.
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
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function texte(v: unknown, max: number): string {
  return String(v ?? "").replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, "").trim().slice(0, max);
}

const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;

function repondre(corps: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(corps), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  const cors = entetesCors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return repondre({ error: "method_not_allowed" }, 405, cors);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return repondre({ error: "invalid_json" }, 400, cors);
  }

  // Piège à robots : champ invisible pour un humain.
  if (texte(body.societe, 200)) return repondre({ ok: true }, 200, cors);

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "inconnue";
  if (tropDeEnvois(ip)) return repondre({ error: "trop_de_demandes" }, 429, cors);

  const prenom = texte(body.prenom, 60);
  const telephone = texte(body.telephone, 40);
  const email = texte(body.email, 160).toLowerCase();
  const zone = texte(body.zone, 160);
  const typologie = texte(body.typologie, 30);
  const projet = texte(body.projet, 20);
  const budget = texte(body.budget, 60);
  const origine = texte(body.origine, 30);
  const accord = body.accord === true;

  if (!prenom || !zone || telephone.replace(/\D/g, "").length < 9 || !accord || !RE_EMAIL.test(email)) {
    return repondre({ error: "champs_manquants" }, 422, cors);
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: sec } = await supabase.from("app_secrets").select("value").eq("name", "lead_inbound_token").single();
  if (!sec?.value) return repondre({ error: "configuration" }, 500, cors);

  const intention = projet === "Investir" ? "Investir" : projet === "Habiter" ? "Habiter" : null;
  const aujourdhui = new Date().toISOString().slice(0, 10);
  const corps = [
    `Demande envoyée depuis le formulaire « plans » (vidéos Quoi de neuf${origine ? ", " + origine : ""})`,
    ``,
    `Prénom : ${prenom}`,
    `Téléphone : ${telephone}`,
    email ? `Email : ${email}` : null,
    `Secteur recherché : ${zone}`,
    typologie ? `Typologie : ${typologie}` : null,
    intention ? `Intention : ${intention}` : null,
    budget ? `Budget : ${budget}` : null,
    ``,
    `Accord de recontact par GLR Immobilier donné le ${aujourdhui}.`,
  ].filter((l) => l !== null).join("\n");

  const payload = {
    vendeur: VENDEUR,
    from: email || "",
    from_name: prenom,
    subject: `Formulaire plans Quoi de neuf — ${prenom}`,
    plain: corps,
    nom: prenom,
    email: email || null,
    telephone,
    budget: budget || null,
    lieu: zone,
    typologie: typologie || null,
  };

  let resultat: any = null;
  try {
    const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/lead-inbound?token=${sec.value}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    resultat = await r.json().catch(() => null);
  } catch (_) {
    return repondre({ error: "envoi_impossible" }, 502, cors);
  }
  if (!resultat || resultat.status === "error" || resultat.status === "ignored") {
    return repondre({ error: "enregistrement_impossible" }, 502, cors);
  }

  // La fiche garde la bonne source, l'intention et la trace de l'accord.
  if (resultat.id) {
    try {
      const { data: actuel } = await supabase.from("contacts").select("source, intention, notes, prenom, nom_confirme").eq("id", resultat.id).single();
      const maj: Record<string, unknown> = {};
      if (actuel && resultat.status === "created") maj.source = SOURCE;
      if (actuel && intention && !actuel.intention) maj.intention = intention;
      if (actuel && !actuel.nom_confirme && !actuel.prenom) maj.prenom = prenom;
      const trace = `[${aujourdhui}] Formulaire plans Quoi de neuf : ${zone}${typologie ? ", " + typologie : ""}${budget ? ", " + budget : ""}. Accord de recontact donné.`;
      maj.notes = actuel?.notes ? actuel.notes + "\n" + trace : trace;
      await supabase.from("contacts").update(maj).eq("id", resultat.id);
    } catch (_) { /* le lead est enregistré : on n'échoue pas pour un affinage */ }
  }

  return repondre({ ok: true, statut: resultat.status }, 200, cors);
});
