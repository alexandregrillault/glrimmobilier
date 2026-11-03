// Test du questionnaire Instagram de Quoi de neuf (supabase/functions/qdn-instagram/questionnaire.ts).
// Lancer : ~/.local/bin/node tests/qdn_questionnaire.mjs
import { demarrerDepuisCommentaire, repondre } from "../supabase/functions/qdn-instagram/questionnaire.ts";

let echecs = 0;
const ok = (cond, msg) => { if (!cond) { echecs++; console.log("ÉCHEC :", msg); } else console.log("ok :", msg); };
const dire = (r) => r.messages.map((m) => m.text + (m.quick_replies ? " [" + m.quick_replies.map((b) => b.title).join(" | ") + "]" : "")).join(" / ");

// 1. Parcours complet depuis un commentaire, avec boutons et une erreur de téléphone
let r = demarrerDepuisCommentaire("camille_93");
ok(r.conv.etape === "zone" && /quelle ville/.test(r.messages[0].text), "commentaire : première question = secteur");
r = repondre(r.conv, "Aubervilliers", null, false); ok(r.conv.etape === "zone_plus" && /Noté : Aubervilliers\. Tu regardes aussi une autre ville/.test(r.messages[0].text), "secteur noté, propose une autre ville");
r = repondre(r.conv, "Pantin et Bobigny", null, false); ok(r.conv.reponses.zone === "Aubervilliers, Pantin, Bobigny" && r.conv.etape === "zone_plus", "plusieurs villes dans un message");
r = repondre(r.conv, "oui", null, false); ok(/Laquelle/.test(r.messages[0].text), "« oui » seul : demande laquelle");
r = repondre(r.conv, "pantin", null, false); ok(r.conv.reponses.zone === "Aubervilliers, Pantin, Bobigny", "ville en double ignorée");
r = repondre(r.conv, "", "ZONE_FINI", false); ok(r.conv.etape === "typologie" && r.messages[0].quick_replies?.length === 5, "« C'est tout » : typologie avec 5 boutons");
r = repondre(r.conv, "T3", "TYPO_T3", false); ok(r.conv.reponses.typologie === "T3" && r.conv.etape === "budget", "typologie par bouton");
ok(r.messages[0].quick_replies.every((b) => b.title.length <= 20), "boutons de la jauge : 20 caractères au plus");
r = repondre(r.conv, "▰▰▰▱▱ 300–400 k€", "BUDGET_3", false); ok(r.conv.reponses.budget === "300 000 à 400 000 €", "budget par bouton");
r = repondre(r.conv, "je m'appelle camille", null, false); ok(r.conv.reponses.prenom === "Camille" && /Merci Camille/.test(r.messages[0].text), "prénom nettoyé");
r = repondre(r.conv, "pas envie", null, false); ok(r.conv.etape === "telephone" && r.conv.essais === 1 && /pas reconnu/.test(r.messages[0].text), "téléphone faux : redemande");
r = repondre(r.conv, "06 12 34 56 78", null, false); ok(r.conv.reponses.telephone === "06 12 34 56 78" && r.conv.etape === "email", "téléphone accepté");
r = repondre(r.conv, "Camille.D @ Gmail.com", null, false); ok(r.conv.reponses.email === "camille.d@gmail.com" && r.conv.etape === "accord", "e-mail nettoyé");
ok(/GLR Immobilier/.test(r.messages[0].text) && /mentions-legales/.test(r.messages[0].text), "l'accord nomme GLR et donne le lien des données");
r = repondre(r.conv, "", "ACCORD_OUI", false); ok(r.creerFiche === true && r.conv.etape === "fini" && /Merci Camille/.test(r.messages[0].text), "accord : fiche à créer");
ok(r.conv.reponses.pseudo === "camille_93", "pseudo gardé pour la fiche");
const fini = r.conv;
r = repondre(fini, "merci !", null, false); ok(r.messages.length === 0, "après la fin, un message ordinaire : le robot se tait");
r = repondre(fini, "et les plans ?", null, false); ok(/déjà noté/.test(r.messages[0].text), "après la fin, « plans » dans la journée : déjà noté");

// 2. Message privé sans parler de plans : invitation, puis refus
r = repondre(null, "Bonjour, vous êtes où ?", null, false); ok(r.conv.etape === "invitation" && r.messages[0].quick_replies?.length === 2, "message privé : invitation avec 2 boutons");
r = repondre(r.conv, "", "PLANS_NON", false); ok(r.conv.etape === "ferme" && /très vite/.test(r.messages[0].text), "invitation refusée");
r = repondre(r.conv, "c'est pour un rdv", null, false); ok(r.messages.length === 0, "ensuite le robot laisse la main");

// 3. Message privé qui parle de plans : démarre tout de suite
r = repondre(null, "Je veux les plans svp", null, false); ok(r.conv.etape === "zone", "« plans » en privé : questionnaire direct");

// 4. Refus de l'accord : rien n'est gardé
let c = { etape: "accord", reponses: { zone: "X", prenom: "Léa", telephone: "0600000000", email: "a@b.fr" }, essais: 0 };
r = repondre(c, "non", null, false); ok(r.conv.etape === "refus" && Object.keys(r.conv.reponses).length === 0 && !r.creerFiche, "accord refusé : réponses effacées");

// 5. STOP en cours de route
c = { etape: "budget", reponses: { zone: "X" }, essais: 0 };
r = repondre(c, "stop", null, false); ok(r.conv.etape === "refus" && /m'arrête/.test(r.messages[0].text), "STOP arrête le questionnaire");

// 6. Trois e-mails faux : renvoi vers le formulaire
c = { etape: "email", reponses: { pseudo: "x" }, essais: 0 };
r = repondre(c, "bof", null, false); r = repondre(r.conv, "toujours pas", null, false); r = repondre(r.conv, "non", null, false);
ok(r.conv.etape === "ferme" && /glrimmobilier\.com\/plans/.test(r.messages[0].text), "après 3 e-mails faux : lien du formulaire");

// 7. Conversation laissée plus de 24 h : la question en cours est reposée
c = { etape: "telephone", reponses: { prenom: "Léa" }, essais: 1 };
r = repondre(c, "06 11 22 33 44", null, true); ok(r.conv.etape === "telephone" && /Merci Léa/.test(r.messages[0].text), "après 24 h : on repose la question");

// 7 bis. Cinq villes d'un coup : on passe directement à la suite
c = { etape: "zone", reponses: {}, essais: 0 };
r = repondre(c, "Saint-Ouen, Clichy, Pantin, Montreuil, Vincennes, Ivry", null, false);
ok(r.conv.etape === "typologie" && r.conv.reponses.zone.split(", ").length === 5 && r.conv.reponses.zone.startsWith("Saint-Ouen"), "5 villes au plus, puis la suite");

// 8. Typologie écrite à la main
c = { etape: "typologie", reponses: {}, essais: 0 };
ok(repondre(c, "un 4 pièces", null, false).conv.reponses.typologie === "T4", "« un 4 pièces » → T4");
ok(repondre(c, "studio", null, false).conv.reponses.typologie === "Studio / T1", "« studio » → Studio / T1");

console.log("\nExemple de messages :", dire(demarrerDepuisCommentaire(null)));
console.log(echecs ? `\n${echecs} échec(s)` : "\nTout est bon.");
process.exit(echecs ? 1 : 0);
