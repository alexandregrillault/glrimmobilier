// Parrainage (www.glrimmobilier.com/parrainage/) -> CRM
//
// Décisions d'Alex du 12/11/2026 : n'importe qui peut parrainer ; carte cadeau de
// 1 000 € au parrain et 500 € au filleul après la signature chez le notaire ;
// le filleul suit l'attribution habituelle des leads du site (Théophile).
//
//   GET  ?code=XXXXXX                 -> { ok, prenom } (prénom du parrain seulement)
//   POST { action: 'inscrire', ... }  -> le parrain reçoit son lien personnel
//   POST { action: 'recommander', ...}-> le parrain donne les coordonnées d'un proche
//   POST { action: 'filleul', code, ...} -> le filleul arrivé par un lien laisse ses coordonnées
//
// Comme site-contact et qdn-plans : on valide, on filtre le spam, puis on délègue à
// lead-inbound (dédoublonnage, fusion, paternité). Jeton lu dans app_secrets.
// Une fiche déjà connue n'est jamais rattachée d'office à un parrain : une note
// le signale et un gérant décide dans le CRM.

import { createClient } from "npm:@supabase/supabase-js@2";

const VENDEUR = "theophile"; // attribution habituelle des leads du site
const SOURCE = "Parrainage";
const SITE = "https://www.glrimmobilier.com";

const ORIGINES_AUTORISEES = [
  "https://www.glrimmobilier.com",
  "https://glrimmobilier.com",
  "https://alexandregrillault.github.io",
];

const FENETRE_MS = 10 * 60 * 1000;
const MAX_PAR_FENETRE = 5;
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

function texte(v: unknown, max: number): string {
  return String(v ?? "").replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, "").trim().slice(0, max);
}
const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;
const RE_CODE = /^[A-Z0-9]{6}$/;
const telOk = (t: string) => t.replace(/\D/g, "").length >= 9;

function repondre(corps: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(corps), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

const sb = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const lien = (code: string) => `${SITE}/parrainage/?p=${code}`;

type Personne = { prenom: string; nom: string; email: string; telephone: string };
function lirePersonne(o: any): Personne {
  return {
    prenom: texte(o?.prenom, 60),
    nom: texte(o?.nom, 80),
    email: texte(o?.email, 160).toLowerCase(),
    telephone: texte(o?.telephone, 40),
  };
}

// Trouve le parrain par son e-mail, sinon le crée. Rattache la fiche CRM du même e-mail si elle existe.
async function parrainDepuis(supabase: any, p: Personne) {
  const { data: existant } = await supabase.from("parrains").select("id, code, prenom").eq("email", p.email).maybeSingle();
  if (existant) return existant;
  let contactId: string | null = null;
  const motif = p.email.replace(/[\\%_]/g, (c) => "\\" + c); // e-mail pris tel quel, pas comme motif
  const { data: fiches } = await supabase.from("contacts").select("id").ilike("email", motif).limit(2);
  if (fiches && fiches.length === 1) {
    const { data: deja } = await supabase.from("parrains").select("id").eq("contact_id", fiches[0].id).maybeSingle();
    if (!deja) contactId = fiches[0].id;
  }
  const { data, error } = await supabase.from("parrains").insert({
    prenom: p.prenom, nom: p.nom || null, email: p.email, telephone: p.telephone || null,
    contact_id: contactId, origine: "site", accord_le: new Date().toISOString(),
  }).select("id, code, prenom").single();
  if (error) throw error;
  return data;
}

async function creerFilleul(
  supabase: any,
  f: Personne & { zone: string; projet: string; message: string },
  parrain: { id: string; prenom: string; nom?: string | null },
  mode: "recommande" | "lien",
) {
  const { data: sec } = await supabase.from("app_secrets").select("value").eq("name", "lead_inbound_token").single();
  if (!sec?.value) throw new Error("configuration");
  const aujourdhui = new Date().toISOString().slice(0, 10);
  const nomComplet = `${f.prenom} ${f.nom}`.trim();
  const parrainNom = `${parrain.prenom} ${parrain.nom || ""}`.trim();
  const intention = f.projet === "Investir" ? "Investir" : f.projet === "Habiter" ? "Habiter" : null;
  const corps = [
    mode === "recommande"
      ? `Recommandé par ${parrainNom} (parrainage GLR, formulaire du site)`
      : `Arrivé par le lien de parrainage de ${parrainNom}`,
    ``,
    `Nom : ${nomComplet}`,
    f.telephone ? `Téléphone : ${f.telephone}` : null,
    f.email ? `Email : ${f.email}` : null,
    f.zone ? `Secteur recherché : ${f.zone}` : null,
    intention ? `Intention : ${intention}` : null,
    f.message ? `\nMessage :\n${f.message}` : null,
    ``,
    mode === "recommande"
      ? `Le parrain certifie que son proche est d'accord pour être contacté (${aujourdhui}).`
      : `Accord de recontact donné le ${aujourdhui}.`,
  ].filter((l) => l !== null).join("\n");

  const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/lead-inbound?token=${sec.value}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      vendeur: VENDEUR,
      from: f.email || "",
      from_name: nomComplet,
      subject: `Parrainage — ${nomComplet} recommandé par ${parrainNom}`,
      plain: corps,
      nom: nomComplet,
      email: f.email || null,
      telephone: f.telephone || null,
      lieu: f.zone || null,
    }),
  });
  const res: any = await r.json().catch(() => null);
  if (!res || res.status === "error" || res.status === "ignored") throw new Error("enregistrement_impossible");
  if (!res.id) return;

  const { data: actuel } = await supabase.from("contacts")
    .select("source, intention, notes, prenom, nom_famille, nom_confirme, parrain_id").eq("id", res.id).single();
  if (!actuel) return;
  const maj: Record<string, unknown> = {};
  const nouvelle = res.status === "created";
  let trace: string;
  if (nouvelle) {
    maj.source = SOURCE;
    maj.parrain_id = parrain.id;
    trace = `[${aujourdhui}] Parrainage : recommandé par ${parrainNom}.`;
  } else if (actuel.parrain_id === parrain.id) {
    trace = `[${aujourdhui}] Parrainage : ${parrainNom} l'a de nouveau recommandé.`;
  } else {
    trace = `[${aujourdhui}] Parrainage : ${parrainNom} dit l'avoir recommandé, mais la fiche existait déjà. Parrain non rattaché : un gérant décide.`;
  }
  if (!actuel.nom_confirme) {
    if (f.prenom && !actuel.prenom) maj.prenom = f.prenom;
    if (f.nom && !actuel.nom_famille) maj.nom_famille = f.nom;
  }
  if (intention && !actuel.intention) maj.intention = intention;
  maj.notes = actuel.notes ? actuel.notes + "\n" + trace : trace;
  await supabase.from("contacts").update(maj).eq("id", res.id);
}

Deno.serve(async (req: Request) => {
  const cors = entetesCors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const supabase = sb();

  if (req.method === "GET") {
    const code = texte(new URL(req.url).searchParams.get("code"), 10).toUpperCase();
    if (!RE_CODE.test(code)) return repondre({ error: "code_invalide" }, 404, cors);
    const { data } = await supabase.from("parrains").select("prenom").eq("code", code).maybeSingle();
    if (!data) return repondre({ error: "code_inconnu" }, 404, cors);
    return repondre({ ok: true, prenom: data.prenom }, 200, cors);
  }
  if (req.method !== "POST") return repondre({ error: "method_not_allowed" }, 405, cors);

  let body: any;
  try { body = await req.json(); } catch { return repondre({ error: "invalid_json" }, 400, cors); }
  if (texte(body.societe, 200)) return repondre({ ok: true }, 200, cors); // piège à robots

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "inconnue";
  if (tropDeEnvois(ip)) return repondre({ error: "trop_de_demandes" }, 429, cors);

  const action = texte(body.action, 20);
  try {
    if (action === "inscrire" || action === "recommander") {
      const p = lirePersonne(body.parrain);
      if (!p.prenom || !p.nom || !RE_EMAIL.test(p.email) || !telOk(p.telephone) || body.accord !== true) {
        return repondre({ error: "champs_manquants" }, 422, cors);
      }
      if (action === "recommander") {
        const f = lirePersonne(body.filleul);
        if (!f.prenom || !telOk(f.telephone) || (f.email && !RE_EMAIL.test(f.email)) || body.accord_filleul !== true) {
          return repondre({ error: "champs_manquants" }, 422, cors);
        }
        if (f.email && f.email === p.email) return repondre({ error: "meme_personne" }, 422, cors);
        const parrain = await parrainDepuis(supabase, p);
        await creerFilleul(supabase, {
          ...f, zone: texte(body.filleul?.zone, 160), projet: texte(body.filleul?.projet, 20), message: texte(body.filleul?.message, 1500),
        }, { id: parrain.id, prenom: p.prenom, nom: p.nom }, "recommande");
        return repondre({ ok: true, code: parrain.code, lien: lien(parrain.code) }, 200, cors);
      }
      const parrain = await parrainDepuis(supabase, p);
      return repondre({ ok: true, code: parrain.code, lien: lien(parrain.code) }, 200, cors);
    }

    if (action === "filleul") {
      const code = texte(body.code, 10).toUpperCase();
      const { data: parrain } = RE_CODE.test(code)
        ? await supabase.from("parrains").select("id, prenom, nom, email").eq("code", code).maybeSingle()
        : { data: null };
      if (!parrain) return repondre({ error: "code_inconnu" }, 404, cors);
      const f = lirePersonne(body.filleul);
      if (!f.prenom || !f.nom || !RE_EMAIL.test(f.email) || !telOk(f.telephone) || body.accord !== true) {
        return repondre({ error: "champs_manquants" }, 422, cors);
      }
      if (parrain.email && parrain.email === f.email) return repondre({ error: "meme_personne" }, 422, cors);
      await creerFilleul(supabase, {
        ...f, zone: texte(body.filleul?.zone, 160), projet: texte(body.filleul?.projet, 20), message: texte(body.filleul?.message, 1500),
      }, parrain, "lien");
      return repondre({ ok: true }, 200, cors);
    }
  } catch (_) {
    return repondre({ error: "enregistrement_impossible" }, 502, cors);
  }
  return repondre({ error: "action_inconnue" }, 400, cors);
});
