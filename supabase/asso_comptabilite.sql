-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  COMPTABILITE : ON NE SUPPRIME RIEN, ON QUALIFIE
--  ---------------------------------------------------------------
--  Toute somme encaissee reste dans la base avec sa vraie date et son
--  vrai montant, essai compris. Ce qui change, c'est seulement de
--  savoir si la ligne vaut adhesion ou non.
--
--    statut = 'actif'  une vraie adhesion, comptee comme telle
--    statut = 'essai'  une somme reellement encaissee, mais qui ne
--                      vaut pas adhesion
--
--  A executer apres asso_dons_repris.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LE VRAI MONTANT DE L'ESSAI DU 29 DECEMBRE
--    L'import avait mis 12 EUR partout. Le formulaire dit 0,01 EUR.
-- ---------------------------------------------------------------------
update asso_adhesions
   set montant = 0.01,
       statut  = 'essai'
 where lower(email) = 'elisabeth.sikora@orange.fr'
   and date_debut = date '2025-12-29';

-- le don de 1 EUR du meme jour : encaisse, mais c'etait le meme essai
alter table asso_dons add column if not exists statut text;

update asso_dons
   set statut = 'essai'
 where lower(email) = 'elisabeth.sikora@orange.fr'
   and fait_le = date '2025-12-29';


-- ---------------------------------------------------------------------
-- 2. LE PAIEMENT DE 12 EUR DU JOUR DEVIENT LA VRAIE ADHESION
-- ---------------------------------------------------------------------
update asso_adhesions
   set email         = 'elisabeth.sikora@orange.fr',
       prenom        = 'Elisabeth',
       nom           = 'Sikora',
       pays          = 'France',
       langue        = 'fr',
       statut        = 'actif',
       numero_membre = 1
 where lower(email) = 'orworldassociation@gmail.com'
   and origine = 'stripe';

-- toutes les autres sont bien des adhesions
update asso_adhesions set statut = 'actif'
 where statut is null or statut not in ('actif','essai');

update asso_dons set statut = 'valide' where statut is null;

-- on rattache au compte du site quand il existe
update asso_adhesions a
   set membre = u.id
  from auth.users u
 where a.membre is null and a.email is not null
   and lower(a.email) = lower(u.email);


-- ---------------------------------------------------------------------
-- 3. LE COMPTEUR PUBLIC NE COMPTE PLUS LES ESSAIS
-- ---------------------------------------------------------------------
create or replace view asso_adherents_nombre as
  select count(*)::int as total
    from asso_adhesions
   where date_fin >= current_date
     and coalesce(statut, 'actif') <> 'essai';

grant select on asso_adherents_nombre to anon, authenticated;

create or replace view asso_dons_total as
  select count(*)::int as nombre,
         coalesce(sum(montant), 0)::numeric(10,2) as somme
    from asso_dons
   where coalesce(statut, 'valide') <> 'essai';

grant select on asso_dons_total to anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. LE JOURNAL COMPTABLE
--    Toutes les sommes encaissees, adhesions et dons confondus, dans
--    l'ordre des dates. C'est cette vue qu'il faut exporter pour la
--    comptabilite : rien n'y manque, pas meme les essais.
-- ---------------------------------------------------------------------
create or replace view asso_journal_comptable as
  select date_debut                       as date_encaissement,
         'adhésion'                       as nature,
         numero_recu                      as piece,
         coalesce(prenom,'') || ' ' || coalesce(nom,'') as personne,
         email,
         pays,
         montant,
         moyen,
         coalesce(statut,'actif')         as statut
    from asso_adhesions
  union all
  select fait_le,
         'don',
         numero_recu,
         coalesce(prenom,'') || ' ' || coalesce(nom,''),
         email,
         pays,
         montant,
         moyen,
         coalesce(statut,'valide')
    from asso_dons
   order by date_encaissement, piece;

-- cette vue contient des noms et des adresses : elle ne sort pas du site
revoke all on asso_journal_comptable from anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. VERIFICATION
-- ---------------------------------------------------------------------
select * from asso_journal_comptable;

select statut, count(*) as lignes, sum(montant) as total
  from asso_journal_comptable
 group by statut
 order by statut;
