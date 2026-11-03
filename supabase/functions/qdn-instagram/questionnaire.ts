// Questionnaire du robot Instagram de Quoi de neuf, question par question dans les messages
// privés (demande d'Alex du 03/11/2026). Module sans accès à la base ni à Instagram : il reçoit
// l'état d'une conversation et la réponse de la personne, et rend le nouvel état, les messages
// à envoyer et, à la fin, s'il faut créer la fiche dans le CRM. Testé par tests/qdn_questionnaire.mjs.
//
// Parcours allégé (décision d'Alex du 03/11/2026) : le premier message explique la démarche
// (5 questions, un conseiller de GLR Immobilier envoie les plans) et recueille l'accord d'un
// bouton ; puis 5 questions numérotées : villes, typologie, budget, prénom et téléphone, e-mail.

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
  { title: "Je ne sais pas", payload: "BUDGET_NSP" }, // 20 caractères au plus par bouton
];
const BUDGET_TEXTE: Record<string, string> = {
  BUDGET_1: "Moins de 200 000 €", BUDGET_2: "200 000 à 300 000 €", BUDGET_3: "300 000 à 400 000 €",
  BUDGET_4: "400 000 à 550 000 €", BUDGET_5: "Plus de 550 000 €",
};
const TYPO_TEXTE: Record<string, string> = {
  TYPO_T1: "Studio / T1", TYPO_T2: "T2", TYPO_T3: "T3", TYPO_T4: "T4", TYPO_T5: "T5 et plus",
};

const DEMARCHE = "Pour recevoir les plans : 5 petites questions (30 secondes), puis un conseiller de GLR Immobilier, " +
  "notre partenaire, t'envoie par e-mail les plans des programmes neufs de ton secteur. Ça te va ? Tes données : " + DONNEES;
const OK_NON: Bouton[] = [{ title: "C'est parti", payload: "PLANS_OUI" }, { title: "Non merci", payload: "PLANS_NON" }];

export const Q = {
  // Après un commentaire « PLANS ».
  debut: (): Message => ({ text: "Salut, c'est Alto de Quoi de neuf. " + DEMARCHE, quick_replies: OK_NON }),
  // Message privé qui ne parle pas de plans.
  invitation: (): Message => ({
    text: "Salut, merci pour ton message, c'est Alto de Quoi de neuf. Tu veux recevoir les plans des programmes neufs de ton secteur ? " + DEMARCHE,
    quick_replies: OK_NON,
  }),
  relance: (): Message => ({ text: "Pour commencer, touche « C'est parti ». Sinon, « Non merci ».", quick_replies: OK_NON }),
  zone: (): Message => ({ text: "1/5 · Dans quelle ville tu cherches ? Tu peux en mettre plusieurs." }),
  typologie: (): Message => ({ text: "2/5 · Quel type de logement ?", quick_replies: TYPOLOGIES }),
  budget: (): Message => ({ text: "3/5 · Ton budget ?", quick_replies: BUDGETS }),
  coordonnees: (): Message => ({ text: "4/5 · Ton prénom et ton numéro ?" }),
  prenom: (): Message => ({ text: "Et ton prénom ?" }),
  telephone: (prenom: string): Message => ({ text: `Merci ${prenom}. Et ton numéro ?` }),
  telephoneEncore: (): Message => ({ text: "Je n'ai pas reconnu un numéro de téléphone. Tu peux l'écrire comme ça : 06 12 34 56 78 ?" }),
  email: (): Message => ({ text: "5/5 · Et ton e-mail, pour recevoir les plans du secteur ?" }),
  emailEncore: (): Message => ({ text: "Je n'ai pas reconnu une adresse e-mail. Par exemple : prenom@gmail.com" }),
  merci: (prenom: string): Message => ({
    text: `Merci ${prenom}, c'est noté. Un conseiller de GLR Immobilier te contacte sous 24 h ouvrées avec les plans du secteur.`,
  }),
  pasPlans: (): Message => ({ text: "Pas de souci. Si tu as une question, écris-la ici, on te répond très vite." }),
  stop: (): Message => ({ text: "C'est noté, je m'arrête là. Tes réponses ne sont pas enregistrées." }),
  dejaNote: (): Message => ({ text: "C'est déjà noté : un conseiller de GLR Immobilier te contacte très vite." }),
  formulaire: (): Message => ({ text: "Pas de souci, tu peux aussi remplir ta demande ici : https://www.glrimmobilier.com/plans/?src=instagram" }),
};

export const parleDePlans = (t: string) => /(^|[^a-z])plans?([^a-z]|$)/i.test(t);
const veutArreter = (t: string) => /^\s*(stop|arr[eê]te)\s*[.!]*\s*$/i.test(t);
const ditOui = (t: string) => /^\s*(oui|ok|d['’]accord|dac|yes|ouais|j['’]accepte|vas-y|go|c['’]est parti|[cç]a me va)\b/i.test(t);
const ditNon = (t: string) => /^\s*(non|no|nan|pas maintenant)\b/i.test(t);
export const RE_EMAIL = /^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$/;

export function telephoneValide(t: string): string | null {
  const brut = t.trim();
  const chiffres = brut.replace(/\D/g, "");
  if (chiffres.length < 9 || chiffres.length > 15) return null;
  if (/[a-z]/i.test(brut.replace(/\s/g, ""))) return null;
  return brut;
}

const MOTS_VIDES = /^(bonjour|bonsoir|salut|hello|coucou|moi|je|mon|ma|voici|voila|voilà|pr[eé]nom|num[eé]ro|portable|mobile|merci|ok|oui)$/i;

// « Camille 06 12 34 56 78 », « 0612345678, Camille », « moi c'est Léa » : prénom et/ou numéro.
export function coordonnees(t: string): { prenom: string | null; telephone: string | null } {
  const m = t.match(/\+?\d[\d\s.\-]{7,}\d/);
  const telephone = m ? telephoneValide(m[0]) : null;
  const reste = (m ? t.replace(m[0], " ") : t)
    .replace(/\b(je m['’]appelle|moi c['’]est|c['’]est|mon num[eé]ro|num[eé]ro|t[eé]l[eé]phone|tel|et|:)\b/gi, " ");
  const mot = reste.split(/[\s,.;!?:]+/).find((w) => /^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'’-]+$/.test(w) && !MOTS_VIDES.test(w));
  const prenom = mot ? mot.charAt(0).toUpperCase() + mot.slice(1).toLowerCase().slice(0, 59) : null;
  return { prenom, telephone };
}

function typologieDepuis(t: string): string {
  const s = t.toLowerCase();
  if (/studio|t1\b|f1\b|1 ?pi/.test(s)) return "Studio / T1";
  const m = s.match(/[tf]\s?([2-9])\b|([2-9])\s?pi/);
  if (m) { const n = Number(m[1] || m[2]); return n >= 5 ? "T5 et plus" : "T" + n; }
  return t.trim().slice(0, 30);
}

// « Aubervilliers, Pantin et Bobigny » → trois villes, sans doublon, 5 au plus.
const MAX_VILLES = 5;
function villes(t: string): string[] {
  const liste: string[] = [];
  for (const v of t.split(/\s*(?:,|;|\/|\+|\bet\b|\bou\b|\n)\s*/i)) {
    const propre = v.trim().replace(/[.!?]+$/, "").slice(0, 60);
    if (propre.length >= 2 && !liste.some((x) => x.toLowerCase() === propre.toLowerCase())) liste.push(propre);
  }
  return liste.slice(0, MAX_VILLES);
}

function nouvelle(etape: string, reponses: Record<string, string> = {}): Conversation {
  return { etape, reponses, essais: 0 };
}
const suite = (etape: string, r: Record<string, string>, m: Message): Resultat => ({ conv: { etape, reponses: r, essais: 0 }, messages: [m] });

// Démarrage depuis un commentaire « PLANS » (le message part en réponse privée au commentaire).
export function demarrerDepuisCommentaire(pseudo: string | null): Resultat {
  return { conv: nouvelle("intro", pseudo ? { pseudo } : {}), messages: [Q.debut()] };
}

// Une réponse de la personne, à l'étape en cours. `payload` vient d'un bouton de réponse rapide.
export function repondre(conv: Conversation | null, texteBrut: string, payload: string | null, expire: boolean): Resultat {
  const texte = (texteBrut || "").trim();

  // Première fois : la démarche et le bouton « C'est parti ».
  if (!conv) return parleDePlans(texte) ? { conv: nouvelle("intro"), messages: [Q.debut()] } : { conv: nouvelle("intro"), messages: [Q.invitation()] };

  // Conversation terminée : le robot ne revient que si la personne reparle de plans ;
  // sinon c'est un humain qui répond.
  if (["fini", "refus", "ferme"].includes(conv.etape)) {
    if (!parleDePlans(texte)) return { conv, messages: [] };
    if (conv.etape === "fini" && !expire) return { conv, messages: [Q.dejaNote()] };
    return { conv: nouvelle("intro", conv.reponses?.pseudo ? { pseudo: conv.reponses.pseudo } : {}), messages: [Q.debut()] };
  }

  if (veutArreter(texte)) return { conv: nouvelle("refus"), messages: [Q.stop()] };

  // Conversation restée en plan plus de 24 h : on repose la question en cours.
  if (expire) return { conv: { ...conv, essais: 0 }, messages: [question(conv)] };

  const r = { ...conv.reponses };
  switch (conv.etape) {
    case "intro":
      // L'accord de recontact par GLR Immobilier est donné ici, avant toute question.
      if (payload === "PLANS_OUI" || ditOui(texte) || parleDePlans(texte)) return suite("zone", r, Q.zone());
      if (payload === "PLANS_NON" || ditNon(texte) || conv.essais >= 1) return { conv: nouvelle("ferme", r.pseudo ? { pseudo: r.pseudo } : {}), messages: [Q.pasPlans()] };
      return { conv: { ...conv, essais: 1 }, messages: [Q.relance()] };
    case "zone":
      if (texte.length < 2) return { conv, messages: [Q.zone()] };
      r.zone = villes(texte).join(", ");
      return suite("typologie", r, Q.typologie());
    case "typologie":
      if (!payload && !texte) return { conv, messages: [Q.typologie()] };
      r.typologie = (payload && TYPO_TEXTE[payload]) || typologieDepuis(texte);
      return suite("budget", r, Q.budget());
    case "budget":
      if (!payload && !texte) return { conv, messages: [Q.budget()] };
      if (payload !== "BUDGET_NSP" && !/^\s*(je )?(ne )?sais pas|^\s*(aucune id[ée]e|nsp)\b/i.test(texte)) {
        r.budget = (payload && BUDGET_TEXTE[payload]) || texte.slice(0, 60);
      }
      return suite("coordonnees", r, Q.coordonnees());
    case "coordonnees": {
      const c = coordonnees(texte);
      if (c.prenom) r.prenom = c.prenom;
      if (c.telephone) r.telephone = c.telephone;
      if (r.prenom && r.telephone) return suite("email", r, Q.email());
      if (r.telephone) return suite("prenom", r, Q.prenom());
      if (r.prenom) return suite("telephone", r, Q.telephone(r.prenom));
      return conv.essais >= 2
        ? { conv: nouvelle("ferme", { pseudo: r.pseudo || "" }), messages: [Q.formulaire()] }
        : { conv: { ...conv, essais: conv.essais + 1 }, messages: [Q.coordonnees()] };
    }
    case "prenom": {
      const p = coordonnees(texte).prenom;
      if (!p) return { conv, messages: [Q.prenom()] };
      r.prenom = p;
      return suite("email", r, Q.email());
    }
    case "telephone": {
      const tel = coordonnees(texte).telephone;
      if (!tel) return conv.essais >= 2
        ? { conv: nouvelle("ferme", { pseudo: r.pseudo || "" }), messages: [Q.formulaire()] }
        : { conv: { ...conv, essais: conv.essais + 1 }, messages: [Q.telephoneEncore()] };
      r.telephone = tel;
      return suite("email", r, Q.email());
    }
    case "email": {
      const email = texte.toLowerCase().replace(/\s/g, "");
      if (!RE_EMAIL.test(email)) return conv.essais >= 2
        ? { conv: nouvelle("ferme", { pseudo: r.pseudo || "" }), messages: [Q.formulaire()] }
        : { conv: { ...conv, essais: conv.essais + 1 }, messages: [Q.emailEncore()] };
      r.email = email;
      return { conv: { etape: "fini", reponses: r, essais: 0 }, messages: [Q.merci(r.prenom || "")], creerFiche: true };
    }
  }
  return { conv, messages: [] };
}

function question(conv: Conversation): Message {
  switch (conv.etape) {
    case "intro": return Q.debut();
    case "zone": return Q.zone();
    case "typologie": return Q.typologie();
    case "budget": return Q.budget();
    case "coordonnees": return Q.coordonnees();
    case "prenom": return Q.prenom();
    case "telephone": return Q.telephone(conv.reponses.prenom || "");
    case "email": return Q.email();
  }
  return Q.zone();
}
