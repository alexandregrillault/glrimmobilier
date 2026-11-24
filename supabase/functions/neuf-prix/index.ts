// Prix des logements d'un programme, pour les pages ville du site
// (www.glrimmobilier.com/neuf/<ville>/<programme>/).
//
// PAS ENCORE DÉPLOYÉE (préparée le 24/11/2026). À déployer avec verify_jwt = false (page publique,
// sans connexion), et seulement après la migration 20261124_neuf_prix.sql.
//
// Décision d'Alex du 24/11/2026 : les prix sont visibles sans compte, les plans non. Les prix ne
// sont écrits ni dans les pages ni dans le dépôt public du site : la page les demande ici à
// l'ouverture, avec la clé publique du programme (jamais l'identifiant de la pige).
//
// Appel  : GET /functions/v1/neuf-prix?p=<clé du programme, 12 caractères>
// Réponse: { "maj": "2026-11-24", "prix": { "<clé du lot>": 245000 }, "prix_tva_reduite": { "<clé du lot>": 215000 } }
//   - seulement les lots libres de type Appartement ou Maison ;
//   - « prix » = prix TVA 20 %, « prix_tva_reduite » = prix TVA 5,5 % (sous conditions de ressources) ;
//     décision d'Alex du 24/11/2026 : la page montre les deux quand les deux existent. Un lot peut
//     n'être que dans l'une des deux listes, ou dans aucune (« sur demande ») ;
//   - jamais de plan, d'image, de numéro de lot, de commission ni de nom d'intranet ;
//   - programme « picking », « sans mandat », hors des villes publiées ou inconnu : 404, même réponse.
//
// Toute la lecture et la limite contre l'aspiration sont dans la fonction SQL neuf_prix_public(),
// réservée à service_role. En cas d'erreur la page affiche « sur demande ».

import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGINES_AUTORISEES = [
  "https://www.glrimmobilier.com",
  "https://glrimmobilier.com",
];

function entetesCors(origin: string | null) {
  const autorise = origin && ORIGINES_AUTORISEES.includes(origin) ? origin : ORIGINES_AUTORISEES[0];
  return {
    "Access-Control-Allow-Origin": autorise,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function repondre(corps: unknown, status: number, cors: Record<string, string>, cache: string) {
  return new Response(JSON.stringify(corps), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": cache },
  });
}

// Empreinte de l'adresse IP : la base ne garde jamais l'adresse elle-même.
async function empreinte(ip: string, sel: string): Promise<string> {
  const octets = new TextEncoder().encode(sel + "|" + ip);
  const hache = new Uint8Array(await crypto.subtle.digest("SHA-256", octets));
  return Array.from(hache).map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

Deno.serve(async (req: Request) => {
  const cors = entetesCors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "GET") return repondre({ error: "method_not_allowed" }, 405, cors, "no-store");

  const cle = (new URL(req.url).searchParams.get("p") || "").trim().toLowerCase();
  if (!/^[0-9a-f]{12}$/.test(cle)) return repondre({ error: "inconnu" }, 404, cors, "no-store");

  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // Adresse du visiteur : celle que voit l'entrée du réseau, sinon la première de la chaîne.
  const ip = req.headers.get("cf-connecting-ip")?.trim() ||
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() || "inconnue";

  let resultat: any = null;
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, cleService);
    const { data, error } = await supabase.rpc("neuf_prix_public", {
      p_cle: cle,
      p_ip: await empreinte(ip, cleService),
    });
    if (error) throw error;
    resultat = data;
  } catch (_) {
    return repondre({ error: "indisponible" }, 503, cors, "no-store");
  }

  if (resultat?.statut === "limite") return repondre({ error: "trop_de_demandes" }, 429, cors, "no-store");
  if (resultat?.statut !== "ok") return repondre({ error: "inconnu" }, 404, cors, "no-store");

  return repondre(
    { maj: resultat.maj, prix: resultat.prix || {}, prix_tva_reduite: resultat.prix_tva_reduite || {} },
    200,
    cors,
    "public, max-age=3600",
  );
});
