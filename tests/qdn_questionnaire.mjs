// Test du questionnaire Instagram de Quoi de neuf (supabase/functions/qdn-instagram/questionnaire.ts).
// Lancer : ~/.local/bin/node tests/qdn_questionnaire.mjs
import { demarrerDepuisCommentaire, repondre, coordonnees, BUDGETS } from "../supabase/functions/qdn-instagram/questionnaire.ts";

let echecs = 0;
const ok = (cond, msg) => { if (!cond) { echecs++; console.log("ÉCHEC :", msg); } else console.log("ok :", msg); };
const dire = (r) => r.messages.map((m) => m.text + (m.quick_replies ? " [" + m.quick_replies.map((b) => b.title).join(" | ") + "]" : "")).join(" / ");

// 1. Parcours complet depuis un commentaire
let r = demarrerDepuisCommentaire("camille_93");
ok(r.conv.etape === "intro" && /5 petites questions/.test(r.messages[0].text) && /GLR Immobilier/.test(r.messages[0].text) && /mentions-legales/.test(r.messages[0].text), "commentaire : démarche expliquée, GLR nommé, lien des données");
ok(r.messages[0].quick_replies?.map((b) => b.title).join("|") === "C'est parti|Non merci", "boutons « C'est parti » / « Non merci »");
r = repondre(r.conv, "", "PLANS_OUI", false); ok(r.conv.etape === "zone" && /^1\/5 · Dans quelle ville/.test(r.messages[0].text), "C'est parti : question 1/5");
r = repondre(r.conv, "Aubervilliers, Pantin et Bobigny", null, false);
ok(r.conv.reponses.zone === "Aubervilliers, Pantin, Bobigny" && r.conv.etape === "typologie" && /^2\/5/.test(r.messages[0].text), "plusieurs villes d'un coup, puis 2/5");
r = repondre(r.conv, "T3", "TYPO_T3", false); ok(r.conv.reponses.typologie === "T3" && /^3\/5/.test(r.messages[0].text), "typologie par bouton, puis 3/5");
ok(!BUDGETS.some((b) => /[▰▱]/.test(b.title)) && BUDGETS.length === 6 && BUDGETS.every((b) => b.title.length <= 20), "budget : boutons simples, « Je ne sais pas » inclus, 20 caractères au plus");
r = repondre(r.conv, "300 à 400 k€", "BUDGET_3", false); ok(r.conv.reponses.budget === "300 000 à 400 000 €" && /^4\/5 · Ton prénom et ton numéro/.test(r.messages[0].text), "budget par bouton, puis 4/5");
r = repondre(r.conv, "Camille 06 12 34 56 78", null, false); ok(r.conv.reponses.prenom === "Camille" && r.conv.reponses.telephone === "06 12 34 56 78" && /^5\/5 · Et ton e-mail, pour recevoir les plans du secteur/.test(r.messages[0].text), "prénom et numéro dans un message, puis 5/5");
r = repondre(r.conv, "Camille.D @ Gmail.com", null, false);
ok(r.creerFiche === true && r.conv.etape === "fini" && /Merci Camille/.test(r.messages[0].text) && /plans du secteur/.test(r.messages[0].text) && r.conv.reponses.email === "camille.d@gmail.com", "e-mail : fiche créée, merci");
ok(r.conv.reponses.pseudo === "camille_93", "pseudo gardé pour la fiche");
const fini = r.conv;
r = repondre(fini, "merci !", null, false); ok(r.messages.length === 0, "après la fin, un message ordinaire : le robot se tait");
r = repondre(fini, "et les plans ?", null, false); ok(/déjà noté/.test(r.messages[0].text), "après la fin, « plans » dans la journée : déjà noté");

// 2. Prénom et numéro séparés, dans un sens ou dans l'autre
let c = { etape: "coordonnees", reponses: {}, essais: 0 };
r = repondre(c, "Bonjour, moi c'est léa", null, false); ok(r.conv.reponses.prenom === "Léa" && r.conv.etape === "telephone" && /Merci Léa\. Et ton numéro/.test(r.messages[0].text), "prénom seul : demande le numéro");
r = repondre(r.conv, "pas envie", null, false); ok(r.conv.etape === "telephone" && /pas reconnu/.test(r.messages[0].text), "numéro faux : redemande");
r = repondre(r.conv, "+33 6 11 22 33 44", null, false); ok(r.conv.reponses.telephone === "+33 6 11 22 33 44" && r.conv.etape === "email", "numéro accepté");
r = repondre(c, "0611223344", null, false); ok(r.conv.etape === "prenom" && r.conv.reponses.telephone === "0611223344", "numéro seul : demande le prénom");
r = repondre(r.conv, "Karim", null, false); ok(r.conv.reponses.prenom === "Karim" && r.conv.etape === "email", "puis le prénom");
ok(coordonnees("06.12.34.56.78 Jean-Marc").prenom === "Jean-marc" || coordonnees("06.12.34.56.78 Jean-Marc").prenom === "Jean-Marc", "numéro avant le prénom composé");

// 3. Budget « je ne sais pas »
c = { etape: "budget", reponses: {}, essais: 0 };
r = repondre(c, "Je ne sais pas", "BUDGET_NSP", false); ok(!r.conv.reponses.budget && r.conv.etape === "coordonnees", "budget inconnu : rien de noté, on continue");
r = repondre(c, "je sais pas trop", null, false); ok(!r.conv.reponses.budget, "« je sais pas » écrit à la main");

// 4. Message privé sans parler de plans : invitation, puis refus ; le robot laisse la main
r = repondre(null, "Bonjour, vous êtes où ?", null, false); ok(r.conv.etape === "intro" && /merci pour ton message/.test(r.messages[0].text) && r.messages[0].quick_replies?.length === 2, "message privé : invitation avec la démarche");
r = repondre(r.conv, "", "PLANS_NON", false); ok(r.conv.etape === "ferme" && /on te répond très vite/.test(r.messages[0].text), "invitation refusée");
r = repondre(r.conv, "c'est pour un rdv", null, false); ok(r.messages.length === 0, "ensuite le robot laisse la main");

// 5. Réponse hors sujet à l'intro : une relance, puis la main aux humains
c = demarrerDepuisCommentaire(null).conv;
r = repondre(c, "Boulogne", null, false); ok(r.conv.etape === "intro" && /C'est parti/.test(r.messages[0].text), "réponse hors bouton : une relance");
r = repondre(r.conv, "Boulogne svp", null, false); ok(r.conv.etape === "ferme", "deuxième fois : main aux humains");
r = repondre(demarrerDepuisCommentaire(null).conv, "oui", null, false); ok(r.conv.etape === "zone", "« oui » écrit vaut « C'est parti »");

// 6. STOP en cours de route
c = { etape: "budget", reponses: { zone: "X" }, essais: 0 };
r = repondre(c, "stop", null, false); ok(r.conv.etape === "refus" && Object.keys(r.conv.reponses).length === 0 && /m'arrête/.test(r.messages[0].text), "STOP arrête et efface");

// 7. Trois e-mails faux : renvoi vers le formulaire
c = { etape: "email", reponses: { pseudo: "x" }, essais: 0 };
r = repondre(c, "bof", null, false); r = repondre(r.conv, "toujours pas", null, false); r = repondre(r.conv, "non", null, false);
ok(r.conv.etape === "ferme" && /glrimmobilier\.com\/plans/.test(r.messages[0].text), "après 3 e-mails faux : lien du formulaire");

// 8. Conversation laissée plus de 24 h : la question en cours est reposée
c = { etape: "telephone", reponses: { prenom: "Léa" }, essais: 1 };
r = repondre(c, "06 11 22 33 44", null, true); ok(r.conv.etape === "telephone" && /Merci Léa/.test(r.messages[0].text), "après 24 h : on repose la question");

// 9. Typologie écrite à la main
c = { etape: "typologie", reponses: {}, essais: 0 };
ok(repondre(c, "un 4 pièces", null, false).conv.reponses.typologie === "T4", "« un 4 pièces » → T4");
ok(repondre(c, "studio", null, false).conv.reponses.typologie === "Studio / T1", "« studio » → Studio / T1");
ok(repondre(c, "T2 ou T3", null, false).conv.reponses.typologie === "T2, T3", "« T2 ou T3 » → T2, T3");
ok(repondre(c, "3 ou 4 pièces", null, false).conv.reponses.typologie === "T3, T4", "« 3 ou 4 pièces » → T3, T4");
ok(repondre(c, "studio, t2", null, false).conv.reponses.typologie === "Studio / T1, T2", "« studio, t2 » → Studio / T1, T2");
ok(repondre(c, "T4/T5", null, false).conv.reponses.typologie === "T4, T5 et plus", "« T4/T5 » → T4, T5 et plus");
ok(repondre(c, "", "TYPO_T3", false).conv.reponses.typologie === "T3", "bouton : un seul choix");
ok(/écris-en plusieurs/.test(repondre({ etape: "zone", reponses: {}, essais: 0 }, "Pantin", null, false).messages[0].text), "la question dit qu'on peut en écrire plusieurs");

console.log("\nExemple :", dire(demarrerDepuisCommentaire(null)));
console.log(echecs ? `\n${echecs} échec(s)` : "\nTout est bon.");
process.exit(echecs ? 1 : 0);
