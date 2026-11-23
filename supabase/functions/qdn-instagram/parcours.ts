// Parcours du robot Instagram de Quoi de neuf (décision d'Alex du 23/11/2026 : « je veux simplement
// que le robot envoie le message »). Plus de questionnaire : à un commentaire ou à un message privé
// qui parle de plans, le robot envoie UN message, le même pour tout le monde, avec un bouton qui
// ouvre le planning de Théophile. C'est la page de rendez-vous qui demande les
// coordonnées et crée la fiche dans le CRM ; le robot ne crée aucune fiche et ne garde aucune réponse.
//
// Module sans accès à la base ni à Instagram : il reçoit l'état d'une conversation et ce que la
// personne écrit, et rend le nouvel état et les messages à envoyer. Testé par tests/qdn_parcours.mjs.
//
// Pourquoi un seul message : Instagram n'autorise qu'un message privé en réponse à un commentaire,
// le suivant ne peut partir que si la personne répond. Le texte et les boutons voyagent donc ensemble.

export type Lien = { title: string; url: string };
// `boutons` : le message part avec des boutons qui ouvrent une page (pas de lien brut dans le texte).
export type Message = { text: string; boutons?: Lien[] };
export type Conversation = { etape: string; reponses: Record<string, string>; essais: number };
export type Resultat = { conv: Conversation | null; messages: Message[] };

// Planning public de Théophile (leads Quoi de neuf chez Théophile, décision d'Alex du 03/11/2026),
// ouvert sur l'appel de 10 minutes (la page lit f=appel ; la personne peut encore choisir la visio).
export const LIEN_PLANNING = "https://www.glrimmobilier.com/rdv/?v=theophile&f=appel";

// Texte et bouton validés par Alex le 23/11/2026 (« c'est bien le bon texte », « mets le bouton »,
// comme avant : un bouton qui ouvre le planning). Un bouton Instagram porte 20 caractères au plus.
export const TEXTE_RDV = "Salut, c'est GLR Immobilier, le média Quoi de neuf. " + String.fromCodePoint(0x1f44b) +
  " Les vrais prix et les plans des programmes neufs, tu ne les verras pas sur les sites d'annonces." +
  " Si ton projet est sérieux, prends 10 minutes avec un conseiller : on cadre ton projet, puis on te montre" +
  " les programmes qui collent, avec les plans et les prix réels.";

export const M = {
  rdv: (): Message => ({
    text: TEXTE_RDV,
    boutons: [{ title: "Voir le planning", url: LIEN_PLANNING }],
  }),
  stop: (): Message => ({ text: "C'est noté, je m'arrête là." }),
  // Reste de l'ancien parcours : la personne à qui le robot avait proposé les plans répond non.
  pasPlans: (): Message => ({ text: "Pas de souci. Si tu as une question, écris-la ici, on te répond très vite." }),
};

export const parleDePlans = (t: string) => /(^|[^a-z])plans?([^a-z]|$)/i.test(t);
export const veutArreter = (t: string) => /^\s*(stop|arr[eê]te)\s*[.!]*\s*$/i.test(t);
const ditNon = (t: string) => /^\s*(non|no|nan|pas maintenant)\b/i.test(t);

const etat = (etape: string, pseudo?: string): Conversation => ({ etape, reponses: pseudo ? { pseudo } : {}, essais: 0 });
// Étapes où le robot a fini de parler : il ne revient que si la personne reparle de plans.
const FINIES = ["planning", "fini", "refus", "ferme"];

// Commentaire qui contient « plan » ou « plans » : le message part en réponse privée au commentaire.
export function demarrerDepuisCommentaire(pseudo: string | null): Resultat {
  return { conv: etat("planning", pseudo || undefined), messages: [M.rdv()] };
}

// Un message privé de la personne. `payload` vient d'un bouton de l'ancien parcours.
// Rend `conv: null` et aucun message quand le robot n'a rien à dire : c'est un humain qui répond.
export function repondre(conv: Conversation | null, texteBrut: string, payload: string | null): Resultat {
  const texte = (texteBrut || "").trim();
  const pseudo = conv?.reponses?.pseudo;

  // « STOP » arrête toujours tout, à n'importe quel moment.
  if (veutArreter(texte)) {
    if (conv?.etape === "refus") return { conv, messages: [] };
    return { conv: etat("refus", pseudo), messages: [M.stop()] };
  }

  // Première fois, ou conversation terminée : le robot ne parle que si la personne parle de plans.
  if (!conv || FINIES.includes(conv.etape)) {
    if (!parleDePlans(texte)) return { conv, messages: [] };
    return { conv: etat("planning", pseudo), messages: [M.rdv()] };
  }

  // Conversation de l'ancien parcours restée en route (questions sur la ville, la typologie…).
  if (conv.etape === "intro" && (payload === "PLANS_NON" || ditNon(texte))) {
    return { conv: etat("ferme", pseudo), messages: [M.pasPlans()] };
  }
  return { conv: etat("planning", pseudo), messages: [M.rdv()] };
}

// Si Instagram refuse le bouton, le même message part en texte, avec l'adresse du planning écrite.
export function enTexte(m: Message): string {
  if (!m.boutons || !m.boutons.length) return m.text;
  return m.text + "\n\n" + m.boutons.map((b) => `${b.title} : ${b.url}`).join("\n");
}
