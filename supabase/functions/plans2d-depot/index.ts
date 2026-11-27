// Dépôt des plans du promoteur convertis en images par le robot de pige (session Pige et robots).
//
// PRÉPARÉE le 27/11/2026, PAS ENCORE DÉPLOYÉE (part avec plans-3d v5 au « déploie » d'Alex).
// verify_jwt = false : le robot n'a que la clé publique et la clé du robot (app_secrets « robot_pige »),
// que la fonction vérifie elle-même avant tout dépôt. Dépend de 20261127_plans_2d.sql et
// 20261127_plans_2d_robot.sql.
//
// Appel : POST { cle_robot, lot_id, cle, plan_url, plan_maj, pages: [WebP en base64, dans l'ordre] }
//         ou, pour un plan illisible : { cle_robot, lot_id, cle, plan_url, plan_maj, pages: [], erreur: "…" }
// Réponse : 200 { ok: true } ; sinon { ok: false, erreur } avec 400 (demande invalide), 403 (clé du robot),
//           404 (lot ou plan inconnu), 413 (image trop lourde), 500/503 (dépôt impossible) : à retenter.
//
// Contrat garanti ici : les images sont déposées d'abord (<cle>/1.webp, 2.webp… dans l'espace privé
// plans2d, en remplaçant l'existant), la ligne de neuf_plans_2d n'est écrite qu'ensuite ; 8 pages au plus,
// 5 Mo par image, WebP seulement ; jamais de suppression.

import { createClient } from "npm:@supabase/supabase-js@2";

const ESPACE = "plans2d";
const PAGES_MAX = 8;
const OCTETS_MAX = 5 * 1024 * 1024;

function repondre(corps: unknown, status: number) {
  return new Response(JSON.stringify(corps), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function base64EnOctets(b64: string): Uint8Array {
  const bin = atob(b64.replace(/^data:[^,]*,/, "").replace(/\s/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Une image WebP commence par « RIFF » puis, à l'octet 8, « WEBP ».
function estWebp(o: Uint8Array): boolean {
  return o.length > 12 &&
    o[0] === 0x52 && o[1] === 0x49 && o[2] === 0x46 && o[3] === 0x46 &&
    o[8] === 0x57 && o[9] === 0x45 && o[10] === 0x42 && o[11] === 0x50;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return repondre({ ok: false, erreur: "method_not_allowed" }, 405);

  let b: Record<string, unknown>;
  try {
    b = await req.json();
  } catch {
    return repondre({ ok: false, erreur: "invalid_json" }, 400);
  }

  const cleRobot = String(b.cle_robot ?? "");
  const lotId = String(b.lot_id ?? "");
  const cle = String(b.cle ?? "").toLowerCase();
  const planUrl = String(b.plan_url ?? "");
  const planMaj = b.plan_maj ? String(b.plan_maj) : null;
  const pages = Array.isArray(b.pages) ? b.pages : null;
  const erreur = b.erreur ? String(b.erreur).slice(0, 500) : "";

  if (!lotId || !/^[0-9a-f]{12}$/.test(cle) || !planUrl || !pages || pages.length > PAGES_MAX) {
    return repondre({ ok: false, erreur: "demande_invalide" }, 400);
  }
  if (pages.length === 0 && !erreur) return repondre({ ok: false, erreur: "demande_invalide" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // 1. Clé du robot, et lot qui a bien ce plan et cette clé publique, avant tout dépôt.
  try {
    const { data: v, error } = await supabase.rpc("robot_plans_2d_verifier", {
      p_cle: cleRobot, p_lot_id: lotId, p_cle_lot: cle, p_source_url: planUrl,
    });
    if (error) throw error;
    if (v === "acces_refuse") return repondre({ ok: false, erreur: "acces_refuse" }, 403);
    if (v !== "ok") return repondre({ ok: false, erreur: "inconnu" }, 404);
  } catch (_) {
    return repondre({ ok: false, erreur: "indisponible" }, 503);
  }

  // 2. Images : toutes vérifiées avant d'en déposer une seule.
  const images: Uint8Array[] = [];
  for (const p of pages) {
    let o: Uint8Array;
    try {
      o = base64EnOctets(String(p));
    } catch (_) {
      return repondre({ ok: false, erreur: "image_illisible" }, 400);
    }
    if (o.length > OCTETS_MAX) return repondre({ ok: false, erreur: "image_trop_lourde" }, 413);
    if (!estWebp(o)) return repondre({ ok: false, erreur: "pas_webp" }, 400);
    images.push(o);
  }

  // 3. Dépôt, page par page (remplace l'existant), puis seulement la ligne en base.
  for (let i = 0; i < images.length; i++) {
    const { error } = await supabase.storage.from(ESPACE).upload(`${cle}/${i + 1}.webp`, images[i], {
      contentType: "image/webp",
      upsert: true,
    });
    if (error) return repondre({ ok: false, erreur: "depot_impossible" }, 500);
  }

  try {
    const { data: res, error } = await supabase.rpc("robot_plans_2d_enregistrer", {
      p_cle: cleRobot,
      p_lot_id: lotId,
      p_cle_lot: cle,
      p_pages: images.length,
      p_source_url: planUrl,
      p_source_maj: planMaj,
      p_erreur: images.length === 0 ? erreur : null,
    });
    if (error) throw error;
    if (res !== "ok") return repondre({ ok: false, erreur: "inconnu" }, 404);
  } catch (_) {
    return repondre({ ok: false, erreur: "indisponible" }, 503);
  }

  return repondre({ ok: true }, 200);
});
