-- Immo-Lead : Nacarat branché le 11/11/2026 après un vrai envoi réussi (Parenthèse, Gif-sur-Yvette). La pige
-- nomme ses programmes « Nom - VILLE », la liste du promoteur « Nom » : le robot essaie la partie avant « - ».
insert into public.denonciation_comptes (plateforme, compte, cp_obligatoire, par_programme, actif, valide_le, note)
values ('immolead', 'nacarat', false, true, true, now(), 'Branché le 11/11/2026 après un vrai envoi réussi ; programme cherché sans le « - VILLE » de la pige')
on conflict do nothing;
