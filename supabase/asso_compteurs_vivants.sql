-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES CHIFFRES DU SITE SE METTENT A JOUR TOUT SEULS
--  ET LE LIVRE COLLABORATIF ACCUEILLE LES HISTOIRES DES FANS
--  ---------------------------------------------------------------
--  Ce qui se compte tout seul desormais :
--    les membres, les pays, les histoires du livre, les projets,
--    les dons, les recits de concert, les articles signales, les votes.
--
--  Les trois chiffres qui n'ont aucune table derriere (concours,
--  evenements, ateliers) se reglent dans la table asso_chiffres,
--  en un seul endroit.
--
--  Les trois histoires deja ecrites dans la page du livre y sont
--  comptees elles aussi, par la ligne histoires_livre. Le jour ou
--  elles passeront dans la base, il suffira de mettre ce chiffre a 0.
--
--  Relancable autant de fois qu'on veut.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LES CHIFFRES QUI SE REGLENT A LA MAIN
-- ---------------------------------------------------------------------
create table if not exists asso_chiffres (
  cle    text primary key,
  valeur int  not null default 0,
  note   text
);

insert into asso_chiffres (cle, valeur, note) values
  ('concours',        1, 'Jeux concours organises'),
  ('evenements',      5, 'Evenements passes et a venir'),
  ('ateliers',        0, 'Ateliers creatifs tenus'),
  ('histoires_livre', 3, 'Histoires ecrites directement dans la page du livre')
on conflict (cle) do nothing;

alter table asso_chiffres enable row level security;

drop policy if exists "chiffres lisibles" on asso_chiffres;
create policy "chiffres lisibles" on asso_chiffres
  for select to anon, authenticated using (true);


-- ---------------------------------------------------------------------
-- 2. LES TROIS PROJETS EN COURS
-- ---------------------------------------------------------------------
insert into asso_projets (titre, categorie)
select v.titre, v.categorie
  from (values
         ('Omar Global Radio Day',   'evenement'),
         ('L''anniversaire d''Omar', 'cadeau'),
         ('Le flashmob mondial',     'creation')
       ) as v(titre, categorie)
 where not exists (select 1 from asso_projets p where p.titre = v.titre);


-- ---------------------------------------------------------------------
-- 3. LE LIVRE COLLABORATIF
--    La table existait, il lui manquait de quoi recevoir une page
--    envoyee par un fan et de quoi la relire avant publication.
-- ---------------------------------------------------------------------
alter table asso_histoires
  add column if not exists signature   text,
  add column if not exists statut      text not null default 'en attente',
  add column if not exists traductions jsonb,
  add column if not exists relecture   boolean default false,
  add column if not exists mineur_ok   boolean default false;

alter table asso_histoires enable row level security;

drop policy if exists "ecrire sa page"      on asso_histoires;
drop policy if exists "lire les publiees"   on asso_histoires;
drop policy if exists "relire sa page"      on asso_histoires;

-- chacun peut deposer sa page, en attente de relecture
create policy "ecrire sa page" on asso_histoires
  for insert to anon, authenticated
  with check (statut = 'en attente');

-- tout le monde lit celles que vous avez publiees
create policy "lire les publiees" on asso_histoires
  for select to anon, authenticated
  using (statut = 'publie');

-- un membre connecte relit la sienne, meme pas encore publiee
create policy "relire sa page" on asso_histoires
  for select to authenticated
  using (membre = auth.uid());


-- ---------------------------------------------------------------------
-- 4. LES COMPTEURS
--    On supprime la vue d'abord : Postgres refuse de changer le type
--    d'une colonne d'une vue existante.
-- ---------------------------------------------------------------------
drop view if exists asso_compteurs;

create view asso_compteurs as
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

  (select count(*)::int from asso_histoires x where x.statut = 'publie')
  + (select coalesce(c.valeur, 0) from asso_chiffres c
      where c.cle = 'histoires_livre')                              as histoires,

  (select count(distinct h.pays)::int
     from asso_histoires h
    where h.statut = 'publie'
      and h.pays is not null and h.pays <> '')                      as pays_histoires,

  (select count(*)::int from asso_projets)                          as projets,

  (select coalesce(sum(v.total), 0)::int
     from asso_votes_chansons_totaux v)                             as votes,

  (select count(*)::int from asso_articles a where a.publie)        as articles,

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
-- 5. VOTRE PAGE DE RELECTURE, AVEC LES HISTOIRES EN PLUS
-- ---------------------------------------------------------------------
create or replace view asso_a_relire as
  select 'récit de concert' as nature, id, cree_le,
         signature          as qui,
         concert            as objet,
         left(recit, 400)   as contenu,
         langue, statut
    from asso_recits
   where statut = 'en attente'
  union all
  select 'article de presse', id, cree_le,
         coalesce(media, ''),
         coalesce(date_parution, ''),
         lien,
         langue, statut
    from asso_presse_signalee
   where statut = 'en attente'
  union all
  select 'page du livre', id, cree_le,
         coalesce(signature, ''),
         coalesce(pays, '') || ' · chapitre ' || coalesce(chapitre::text, '?'),
         left(texte, 400),
         langue, statut
    from asso_histoires
   where statut = 'en attente'
   order by cree_le desc;

revoke all on asso_a_relire from anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. VERIFICATION
-- ---------------------------------------------------------------------
select * from asso_compteurs;
