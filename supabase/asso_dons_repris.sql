-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES 8 DONS DEJA FAITS, REPRIS DE L'ANCIEN SITE
--  ---------------------------------------------------------------
--  Source : l'export du formulaire MEMBERSHIP 2026, colonne Donation.
--  La date du don est celle de l'envoi du formulaire : les deux ont
--  ete regles ensemble.
--  Les numeros de recu suivent l'ordre des dates, sans trou.
--  A executer APRES asso_dons_fiche.sql. Relancable sans rien doubler.
-- =====================================================================

insert into asso_dons
  (email, prenom, nom, pays, langue, montant, moyen, fait_le, numero_recu, origine)
values
  ('elisabeth.sikora@orange.fr',  'Elisabeth','Sikora',     'France',   'fr',  1.00, 'ancien site', date '2025-12-29', 'DON-2025-001', 'reprise'),
  ('paulinahellstrand@gmail.com', 'Paulina',  'Hellstrand', 'Suède',    'sv',  5.00, 'ancien site', date '2026-01-01', 'DON-2026-001', 'reprise'),
  ('kingawieslawa@gazeta.pl',     'Kinga',    'Jarguz',     'Pologne',  'en', 50.00, 'ancien site', date '2026-01-01', 'DON-2026-002', 'reprise'),
  ('f_muurling@hotmail.com',      'Frieda',   'Muurling',   'Pays-Bas', 'en', 12.00, 'ancien site', date '2026-01-01', 'DON-2026-003', 'reprise'),
  ('betty_boo2004@hotmail.com',   'Valerie',  'Letourneau', 'Canada',   'fr',  5.00, 'ancien site', date '2026-01-02', 'DON-2026-004', 'reprise'),
  ('contact@kimcass.fr',          'Peggy',    'Flament',    'France',   'fr',  5.00, 'ancien site', date '2026-01-08', 'DON-2026-005', 'reprise'),
  ('lucie.frontczyk75@gmail.com', 'Lucie',    'Frontczyk',  'France',   'fr',  5.00, 'ancien site', date '2026-01-12', 'DON-2026-006', 'reprise'),
  ('lives@gmx.at',                'Olivia',   'Gfrerer',    'Autriche', 'de', 20.00, 'ancien site', date '2026-04-02', 'DON-2026-007', 'reprise')
on conflict do nothing;

-- on les rattache aux comptes qui existent deja
update asso_dons d
   set membre = u.id
  from auth.users u
 where d.membre is null and d.email is not null
   and lower(d.email) = lower(u.email);


-- ---------------------------------------------------------------------
--  LE MONTANT DE VOTRE PROPRE ADHESION
--  ---------------------------------------------------------------
--  Le formulaire indique 0,01 EUR pour vous, et non 12 EUR comme pour
--  les dix autres. Si c'etait un essai que vous avez fait au moment de
--  mettre le formulaire en place, enlevez les deux tirets de la ligne
--  ci-dessous et relancez la. Sinon, laissez la telle quelle.
--
-- update asso_adhesions set montant = 0.01
--  where email = 'elisabeth.sikora@orange.fr' and origine = 'reprise';


-- ---------------------------------------------------------------------
--  VERIFICATION
-- ---------------------------------------------------------------------
select numero_recu, prenom, nom, pays, montant, fait_le, moyen
  from asso_dons
 order by fait_le, numero_recu;

select * from asso_dons_total;
