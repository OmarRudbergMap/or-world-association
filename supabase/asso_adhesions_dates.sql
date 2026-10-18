-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES ADHESIONS AVEC LEURS VRAIES DATES
--  ET LA REPRISE DES 11 ADHERENTS DE L'ANCIEN SITE
--  ---------------------------------------------------------------
--  A executer dans le projet Supabase de l'ASSOCIATION
--  (gkineosvtpswcbflqvyu), onglet SQL Editor, puis le bouton Run.
--  Le script peut etre relance sans rien doubler ni rien casser.
--
--  Etat constate avant execution : la table asso_adhesions existe,
--  elle est vide, et contient deja id, membre, annee, montant,
--  moyen, statut et cree_le.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LES COLONNES QUI MANQUENT
--    Une adhesion dure un an a partir du jour du paiement, il faut donc
--    une date de debut et une date de fin. Elle doit aussi pouvoir
--    exister avant que la personne ait un compte sur le site : on la
--    retrouve alors par son adresse e-mail, et le rattachement se fait
--    tout seul le jour ou elle s'inscrit (voir le point 4).
-- ---------------------------------------------------------------------
alter table asso_adhesions
  add column if not exists email       text,
  add column if not exists prenom      text,
  add column if not exists nom         text,
  add column if not exists pays        text,
  add column if not exists date_debut  date,
  add column if not exists date_fin    date,
  add column if not exists numero_recu text,      -- numerotation continue, sans trou
  add column if not exists droit_image boolean,   -- la personne autorise sa photo
  add column if not exists origine     text,      -- d'ou vient la ligne
  add column if not exists relance_30  timestamptz,  -- rappel 30 jours envoye le
  add column if not exists relance_7   timestamptz,  -- rappel 7 jours envoye le
  add column if not exists relance_0   timestamptz;  -- rappel du jour envoye le

-- le membre peut rester vide tant que la personne n'a pas de compte
do $$
begin
  alter table asso_adhesions alter column membre drop not null;
exception when others then null;
end $$;

-- une seule adhesion par personne et par date de debut
create unique index if not exists asso_adhesions_unique
  on asso_adhesions (lower(email), date_debut);

create index if not exists asso_adhesions_fin    on asso_adhesions (date_fin);
create index if not exists asso_adhesions_membre on asso_adhesions (membre);


-- ---------------------------------------------------------------------
-- 2. LES 11 ADHERENTS VENUS DE L'ANCIEN SITE
--    La date de debut est la date d'envoi de leur formulaire.
--    La date de fin est calculee : un an plus tard, moins un jour.
--    Les numeros de recu suivent l'ordre des dates, sans trou.
-- ---------------------------------------------------------------------
insert into asso_adhesions
  (email, prenom, nom, pays, date_debut, date_fin, numero_recu, droit_image, moyen, origine, annee)
select
  x.email, x.prenom, x.nom, x.pays,
  x.debut,
  (x.debut + interval '1 year' - interval '1 day')::date,
  x.recu, x.image, 'ancien site', 'reprise',
  extract(year from x.debut)::int
from (values
  ('elisabeth.sikora@orange.fr',  'Elisabeth','Sikora',     'France',     date '2025-12-29', 'ADH-2025-001', true ),
  ('kingawieslawa@gazeta.pl',     'Kinga',    'Jarguz',     'Pologne',    date '2026-01-01', 'ADH-2026-001', true ),
  ('paulinahellstrand@gmail.com', 'Paulina',  'Hellstrand', 'Suède',      date '2026-01-01', 'ADH-2026-002', true ),
  ('f_muurling@hotmail.com',      'Frieda',   'Muurling',   'Pays-Bas',   date '2026-01-01', 'ADH-2026-003', true ),
  ('betty_boo2004@hotmail.com',   'Valerie',  'Letourneau', 'Canada',     date '2026-01-02', 'ADH-2026-004', true ),
  ('dcalhoon2323@gmail.com',      'Danielle', 'Calhoon',    'États-Unis', date '2026-01-03', 'ADH-2026-005', true ),
  ('contact@kimcass.fr',          'Peggy',    'Flament',    'France',     date '2026-01-08', 'ADH-2026-006', true ),
  ('elcerron@hotmail.com',        'Consuelo', 'Consuelo',   'Espagne',    date '2026-01-11', 'ADH-2026-007', false),
  ('lucie.frontczyk75@gmail.com', 'Lucie',    'Frontczyk',  'France',     date '2026-01-12', 'ADH-2026-008', true ),
  ('quentincloe@wanadoo.fr',      'France',   'Reymond',    'France',     date '2026-01-20', 'ADH-2026-009', true ),
  ('lives@gmx.at',                'Olivia',   'Gfrerer',    'Autriche',   date '2026-04-02', 'ADH-2026-010', false)
) as x(email, prenom, nom, pays, debut, recu, image)
on conflict (lower(email), date_debut) do nothing;

-- Le montant verse par ces 11 personnes.
-- CHANGEZ LE CHIFFRE ci-dessous s'il ne s'agit pas de 12 euros.
update asso_adhesions set montant = 12
 where origine = 'reprise' and montant is null;

-- la colonne statut existait deja : on la remplit si elle l'accepte
do $$
begin
  update asso_adhesions set statut = 'actif'
   where origine = 'reprise' and statut is null;
exception when others then null;
end $$;


-- ---------------------------------------------------------------------
-- 3. LES VUES
-- ---------------------------------------------------------------------

-- combien d'adherents a jour, pour le compteur du site.
-- Aucune donnee personnelle ne sort d'ici.
create or replace view asso_adherents_nombre as
  select count(*)::int as total
    from asso_adhesions
   where date_fin >= current_date;

-- les adhesions qui arrivent a echeance, pour les relances.
create or replace view asso_adhesions_a_relancer as
  select id, email, prenom, nom, pays, date_debut, date_fin,
         (date_fin - current_date) as jours_restants,
         relance_30, relance_7, relance_0
    from asso_adhesions
   where date_fin >= current_date - 1
     and date_fin <= current_date + 30
   order by date_fin;

-- Cette vue contient des adresses e-mail et des noms : elle ne doit
-- jamais etre lisible depuis le site. Elle sert uniquement ici, dans
-- l'editeur SQL, et plus tard a la tache automatique de relance.
revoke all on asso_adhesions_a_relancer from anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. LE RATTACHEMENT AUTOMATIQUE
--    Le jour ou une de ces personnes cree son compte avec la meme
--    adresse e-mail, son adhesion se rattache toute seule a son compte.
-- ---------------------------------------------------------------------
create or replace function asso_rattacher_adhesions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update asso_adhesions a
     set membre = new.id
    from auth.users u
   where u.id = new.id
     and a.membre is null
     and a.email is not null
     and lower(a.email) = lower(u.email);
  return new;
end;
$$;

drop trigger if exists asso_rattacher on asso_membres;
create trigger asso_rattacher
  after insert on asso_membres
  for each row execute function asso_rattacher_adhesions();

-- on rattache tout de suite celles dont le compte existe deja
update asso_adhesions a
   set membre = u.id
  from auth.users u
 where a.membre is null
   and a.email is not null
   and lower(a.email) = lower(u.email);


-- ---------------------------------------------------------------------
-- 5. LES DROITS D'ACCES
--    Le site public ne doit jamais pouvoir lire les e-mails et les noms.
--    Chacun lit sa propre adhesion, et rien d'autre.
-- ---------------------------------------------------------------------
alter table asso_adhesions enable row level security;

drop policy if exists "adhesion lisible par son proprietaire" on asso_adhesions;
create policy "adhesion lisible par son proprietaire"
  on asso_adhesions for select
  using (membre = auth.uid());

-- le compteur public passe par la vue, jamais par la table
grant select on asso_adherents_nombre to anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. VERIFICATION
--    Vous devez voir 11 lignes, puis le nombre d'adherents a jour.
-- ---------------------------------------------------------------------
select numero_recu, prenom, nom, pays, date_debut, date_fin,
       (date_fin - current_date) as jours_restants, montant, droit_image
  from asso_adhesions
 where origine = 'reprise'
 order by date_debut;

select * from asso_adherents_nombre;
