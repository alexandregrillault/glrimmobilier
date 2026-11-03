// Questionnaire du robot Instagram de Quoi de neuf, question par question dans les messages
// privés (demande d'Alex du 03/11/2026). Module sans accès à la base ni à Instagram : il reçoit
// l'état d'une conversation et la réponse de la personne, et rend le nouvel état, les messages
// à envoyer et, à la fin, s'il faut créer la fiche dans le CRM. Testé par tests/qdn_questionnaire.mjs.

export type Bouton = { title: string; payload: string };
export type Message = { text: string; quick_replies?: Bouton[] };
export type Conversation = { etape: string; reponses: Record<string, string>; essais: number };
export type Resultat = { conv: Conversation; messages: Message[]; creerFiche?: boolean };

export const DONNEES = "https://www.glrimmobilier.com/mentions-legales/";

export const TYPOLOGIES: Bouton[] = [
  { title: "Studio / T1", payload: "TYPO_T1" },
  { title: "T2", payload: "TYPO_T2" },
  { title: "T3", payload: "TYPO_T3" },
  { title: "T4", payload: "TYPO_T4" },
  { title: "T5 et plus", payload: "TYPO_T5" },
];
export const BUDGETS: Bouton[] = [
  { title: "Moins de 200 k€", payload: "BUDGET_1" },
  { title: "200 à 300 k€", payload: "BUDGET_2" },
  { title: "300 à 400 k€", payload: "BUDGET_3" },
  { title: "400 à 550 k€", payload: "BUDGET_4" },
  { title: "Plus de 550 k€", payload: "BUDGET_5" },
];
const BUDGET_TEXTE: Record<string, string> = {
  BUDGET_1: "Moins de 200 000 €", BUDGET_2: "200 000 à 300 000 €", BUDGET_3: "300 000 à 400 000 €",
  BUDGET_4: "400 000 à 550 000 €", BUDGET_5: "Plus de 550 000 €",
};
const TYPO_TEXTE: Record<string, string> = {
  TYPO_T1: "Studio / T1", TYPO_T2: "T2", TYPO_T3: "T3", TYPO_T4: "T4", TYPO_T5: "T5 et plus",
};

export const Q = {
  debut: (): Message => ({
    text: "Salut, c'est Alto de Quoi de neuf. Je t'envoie les plans des programmes neufs de ton secteur. Pour commencer : tu cherches dans quelle ville ou quel secteur ?",
  }),
  invitation: (): Message => ({
    text: "Salut, merci pour ton message. Tu veux recevoir les plans des programmes neufs de ton secteur ?",
    quick_replies: [{ title: "Oui, envoie-les", payload: "PLANS_OUI" }, { title: "Non merci", payload: "PLANS_NON" }],
  }),
  zone: (): Message => ({ text: "Tu cherches dans quelle ville ou quel secteur ?" }),
  typologie: (): Message => ({ text: "Quel type de logement ?", quick_replies: TYPOLOGIES }),
  budget: (): Message => ({ text: "Ton budget, environ ?", quick_replies: BUDGETS }),
  prenom: (): Message => ({ text: "Et ton prénom ?" }),
  telephone: (prenom: string): Message => ({ text: `Merci ${prenom}. Ton numéro de téléphone ?` }),
  telephoneEncore: (): Message => ({ text: "Je n'ai pas reconnu un numéro de téléphone. Tu peux l'écrire comme ça : 06 12 34 56 78 ?" }),
  email: (): Message => ({ text: "Ton e-mail, pour recevoir les plans ?" }),
  emailEncore: (): Message => ({ text: "Je n'ai pas reconnu une adresse e-mail. Par exemple : prenom@gmail.com" }),
  accord: (): Message => ({
    text: "Dernière étape : c'est un conseiller de GLR Immobilier, notre partenaire, qui t'envoie les plans. " +
      "Tu acceptes qu'il te contacte par téléphone, SMS ou e-mail ? Tes données : " + DONNEES,
    quick_replies: [{ title: "Oui, j'accepte", payload: "ACCORD_OUI" }, { title: "Non", payload: "ACCORD_NON" }],
  }),
  merci: (prenom: string): Message => ({
    text: `Merci ${prenom}, c'est noté. Un conseiller de GLR Immobilier te contacte sous 24 h ouvrées avec les plans des programmes neufs de ton secteur.`,
  }),
  refus: (): Message => ({ text: "Pas de souci, je n'enregistre rien. Si tu changes d'avis, commente PLANS sous une vidéo." }),
  pasPlans: (): Message => ({ text: "Ok, on te répond ici très vite." }),
  stop: (): Message => ({ text: "C'est noté, je m'arrête là. Tes réponses ne sont pas enregistrées." }),
  dejaNote: (): Message => ({ text: "C'est déjà noté : un conseiller de GLR Immobilier te contacte très vite." }),
  formulaire: (): Message => ({ text: "Pas de souci, tu peux aussi remplir ta demande ici : https://www.glrimmobilier.com/plans/?src=instagram" }),
};

export const parleDePlans = (t: string) => /(^|[^a-z])plans?([^a-z]|$)/i.test(t);
const veutArreter = (t: string) => /^\s*(stop|arr[eê]te)\s*[.!]*\s*$/i.test(t);
const ditOui = (t: string) => /^\s*(oui|ok|d'accord|dac|yes|ouais|j'accepte|vas-y|go)\b/i.test(t);
const ditNon = (t: string) => /^\s*(non|no|nan|pas maintenant)\b/i.test(t);
export const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;

export function telephoneValide(t: string): string | null {
  const brut = t.trim();
  const chiffres = brut.replace(/\D/g, "");
  if (chiffres.length < 9 || chiffres.length > 15) return null;
  if (/[a-z]/i.test(brut.replace(/\s/g, ""))) return null;
  return brut;
}

function typologieDepuis(t: string): string {
  const s = t.toLowerCase();
  if (/studio|t1\b|f1\b|1 ?pi/.test(s)) return "Studio / T1";
  const m = s.match(/[tf]\s?([2-9])\b|([2-9])\s?pi/);
  if (m) { const n = Number(m[1] || m[2]); return n >= 5 ? "T5 et plus" : "T" + n; }
  return t.trim().slice(0, 30);
}

function nouvelle(etape: string, reponses: Record<string, string> = {}): Conversation {
  return { etape, reponses, essais: 0 };
}

// Démarrage depuis un commentaire « PLANS » (le message part en réponse privée au commentaire).
export function demarrerDepuisCommentaire(pseudo: string | null): Resultat {
  return { conv: nouvelle("zone", pseudo ? { pseudo } : {}), messages: [Q.debut()] };
}

// Une réponse de la personne, à l'étape en cours. `payload` vient d'un bouton de réponse rapide.
export function repondre(conv: Conversation | null, texteBrut: string, payload: string | null, expire: boolean): Resultat {
  const texte = (texteBrut || "").trim();

  // Première fois : on propose les plans (ou on démarre tout de suite si le message en parle).
  if (!conv) return parleDePlans(texte) ? { conv: nouvelle("zone"), messages: [Q.debut()] } : { conv: nouvelle("invitation"), messages: [Q.invitation()] };

  // Conversation terminée : le robot ne revient que si la personne reparle de plans ;
  // sinon c'est un humain qui répond.
  if (["fini", "refus", "ferme"].includes(conv.etape)) {
    if (!parleDePlans(texte)) return { conv, messages: [] };
    if (conv.etape === "fini" && !expire) return { conv, messages: [Q.dejaNote()] };
    return { conv: nouvelle("zone", conv.reponses?.pseudo ? { pseudo: conv.reponses.pseudo } : {}), messages: [Q.debut()] };
  }

  if (veutArreter(texte)) return { conv: nouvelle("refus"), messages: [Q.stop()] };

  // Conversation restée en plan plus de 24 h : on repose la question en cours.
  if (expire) return { conv: { ...conv, essais: 0 }, messages: [question(conv)] };

  const r = { ...conv.reponses };
  switch (conv.etape) {
    case "invitation":
      if (payload === "PLANS_OUI" || ditOui(texte) || parleDePlans(texte)) return { conv: nouvelle("zone"), messages: [Q.zone()] };
      return { conv: nouvelle("ferme"), messages: [Q.pasPlans()] };
    case "zone":
      if (texte.length < 2) return { conv, messages: [Q.zone()] };
      r.zone = texte.slice(0, 160);
      return { conv: { etape: "typologie", reponses: r, essais: 0 }, messages: [Q.typologie()] };
    case "typologie":
      if (!payload && !texte) return { conv, messages: [Q.typologie()] };
      r.typologie = (payload && TYPO_TEXTE[payload]) || typologieDepuis(texte);
      return { conv: { etape: "budget", reponses: r, essais: 0 }, messages: [Q.budget()] };
    case "budget":
      if (!payload && !texte) return { conv, messages: [Q.budget()] };
      r.budget = (payload && BUDGET_TEXTE[payload]) || texte.slice(0, 60);
      return { conv: { etape: "prenom", reponses: r, essais: 0 }, messages: [Q.prenom()] };
    case "prenom": {
      const prenom = texte.replace(/^(je m'appelle|moi c'est|c'est)\s+/i, "").split(/[\s,.!]+/)[0]?.slice(0, 60) || "";
      if (!prenom) return { conv, messages: [Q.prenom()] };
      r.prenom = prenom.charAt(0).toUpperCase() + prenom.slice(1);
      return { conv: { etape: "telephone", reponses: r, essais: 0 }, messages: [Q.telephone(r.prenom)] };
    }
    case "telephone": {
      const tel = telephoneValide(texte);
      if (!tel) return conv.essais >= 2
        ? { conv: nouvelle("ferme", { pseudo: r.pseudo || "" }), messages: [Q.formulaire()] }
        : { conv: { ...conv, essais: conv.essais + 1 }, messages: [Q.telephoneEncore()] };
      r.telephone = tel;
      return { conv: { etape: "email", reponses: r, essais: 0 }, messages: [Q.email()] };
    }
    case "email": {
      const email = texte.toLowerCase().replace(/\s/g, "");
      if (!RE_EMAIL.test(email)) return conv.essais >= 2
        ? { conv: nouvelle("ferme", { pseudo: r.pseudo || "" }), messages: [Q.formulaire()] }
        : { conv: { ...conv, essais: conv.essais + 1 }, messages: [Q.emailEncore()] };
      r.email = email;
      return { conv: { etape: "accord", reponses: r, essais: 0 }, messages: [Q.accord()] };
    }
    case "accord":
      if (payload === "ACCORD_OUI" || ditOui(texte)) {
        return { conv: { etape: "fini", reponses: r, essais: 0 }, messages: [Q.merci(r.prenom || "")], creerFiche: true };
      }
      if (payload === "ACCORD_NON" || ditNon(texte)) return { conv: nouvelle("refus"), messages: [Q.refus()] };
      return { conv, messages: [Q.accord()] };
  }
  return { conv, messages: [] };
}

function question(conv: Conversation): Message {
  switch (conv.etape) {
    case "invitation": return Q.invitation();
    case "zone": return Q.zone();
    case "typologie": return Q.typologie();
    case "budget": return Q.budget();
    case "prenom": return Q.prenom();
    case "telephone": return Q.telephone(conv.reponses.prenom || "");
    case "email": return Q.email();
    case "accord": return Q.accord();
  }
  return Q.zone();
}
