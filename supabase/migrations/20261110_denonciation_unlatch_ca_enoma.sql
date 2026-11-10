-- Branchement d'Unlatch, espaces Crédit Agricole et Enoma (10/11/2026, « valide » d'Alex) : premiers envois
-- réels réussis (Fernando Sutil, 3 programmes Les Lumières Pleyel ; Morgane Lafagne, Gambetta), retrouvés
-- dans les dénonciations de chaque espace.
-- Le lancement manuel du Crédit Agricole avait noté les 3 programmes sur une seule ligne (« A§B§C ») :
-- on la remet à un programme par ligne, comme le fait le passage horaire.
insert into public.denonciations (contact_id, plateforme, compte, promoteur, programme, ville, statut, detail,
                                  preuve, fait_le, civilite, nom_utilise, nom_source)
select d.contact_id, d.plateforme, d.compte, d.promoteur, p, d.ville, d.statut, d.detail, d.preuve, d.fait_le,
       d.civilite, d.nom_utilise, d.nom_source
from public.denonciations d, unnest(string_to_array(d.programme, '§')) with ordinality as u(p, n)
where d.id = 195 and d.programme like '%§%' and u.n > 1;

update public.denonciations set programme = split_part(programme, '§', 1)
where id = 195 and programme like '%§%';

update public.denonciation_comptes set actif = true, valide_le = now()
where plateforme = 'unlatch' and compte in ('unlatch_credit-agricole', 'unlatch_enoma');
