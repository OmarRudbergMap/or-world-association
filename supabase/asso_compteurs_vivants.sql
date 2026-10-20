-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES CHIFFRES DU SITE SE METTENT A JOUR TOUT SEULS
--  ---------------------------------------------------------------
--  Sous les compteurs de l'accueil, le site promet : « ces chiffres se
--  mettent a jour automatiquement ». C'etait faux : ils etaient ecrits
--  en dur dans la page. Ce script rend la promesse vraie.
--
--  Ce qui se compte tout seul :
--    les membres, les pays, les histoires du livre, les projets,
--    les dons, les recits de concert, les articles du blog, les votes.
--
--  Ce qui n'a pas de table et se regle a la main, en un seul endroit :
--    les concours, les evenements, les ateliers. Il suffit de changer
--    un chiffre dans la table asso_chiffres et le site suit.
--
--  Relancable autant de fois qu'on veut.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LES QUELQUES CHIFFRES QUI N'ONT PAS DE TABLE
-- ---------------------------------------------------------------------
create table if not exists asso_chiffres (
  cle    text primary key,
  valeur int  not null default 0,
  note   text
);

insert into asso_chiffres (cle, valeur, note) values
  ('concours',   1, 'Jeux concours organises'),
  ('evenements', 5, 'Evenements passes et a venir'),
  ('ateliers',   0, 'Ateliers creatifs tenus')
on conflict (cle) do nothing;

alter table asso_chiffres enable row level security;

drop policy if exists "chiffres lisibles" on asso_chiffres;
create policy "chiffres lisibles" on asso_chiffres
  for select to anon, authenticated using (true);


-- ---------------------------------------------------------------------
-- 2. LES TROIS PROJETS EN COURS
--    Pour que le compteur des projets compte quelque chose de vrai.
-- ---------------------------------------------------------------------
insert into asso_projets (titre, categorie)
select v.titre, v.categorie
  from (values
         ('Omar Global Radio Day',            'evenement'),
         ('L''anniversaire d''Omar',          'cadeau'),
         ('Le flashmob mondial',              'creation')
       ) as v(titre, categorie)
 where not exists (select 1 from asso_projets p where p.titre = v.titre);


-- ---------------------------------------------------------------------
-- 3. LES COMPTEURS
--    Les sept premieres colonnes gardent leur nom et leur ordre :
--    la vue existe deja et on ne peut que lui en ajouter.
-- ---------------------------------------------------------------------
create or replace view asso_compteurs as
select
  (select count(*)::int
     from asso_adhesions a
    where a.date_fin >= current_date
      and coalesce(a.statut, 'actif') <> 'essai')                   as membres,

  (select count(distinct a.pays)::int
     from asso_adhesions a
    where a.date_fin >= current_date
      and coalesce(a.statut, 'actif') <> 'essai'
      and a.pays is not null and a.pays <> '')                      as pays,

  (select count(*)::int from asso_histoires)                        as histoires,

  (select count(distinct h.pays)::int
     from asso_histoires h
    where h.pays is not null and h.pays <> '')                      as pays_histoires,

  (select count(*)::int from asso_projets)                          as projets,

  (select coalesce(sum(v.total), 0)::int
     from asso_votes_chansons_totaux v)                             as votes,

  (select count(*)::int from asso_articles a where a.publie)        as articles,

  -- les colonnes ajoutees
  (select coalesce(d.nombre, 0) from asso_dons_total d)             as dons_nombre,
  (select coalesce(d.somme, 0)  from asso_dons_total d)             as dons_somme,
  (select count(*)::int from asso_recits r
    where r.statut = 'publie')                                      as recits,
  (select count(*)::int from asso_presse_signalee p
    where p.statut = 'publie')                                      as presse,
  (select coalesce(c.valeur, 0) from asso_chiffres c
    where c.cle = 'concours')                                       as concours,
  (select coalesce(c.valeur, 0) from asso_chiffres c
    where c.cle = 'evenements')                                     as evenements,
  (select coalesce(c.valeur, 0) from asso_chiffres c
    where c.cle = 'ateliers')                                       as ateliers;

grant select on asso_compteurs to anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. VERIFICATION
-- ---------------------------------------------------------------------
select * from asso_compteurs;
