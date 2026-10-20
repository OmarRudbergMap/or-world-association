-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES TROIS HISTOIRES DE LA PAGE ENTRENT DANS LE COMPTE
--  ---------------------------------------------------------------
--  Le compteur des pays des histoires annonçait 0 alors qu'il y a
--  deux pays : les trois histoires vivent dans la page du livre, la
--  base ne les connaissait pas.
--
--  Plutot que de bricoler un chiffre a la main, on inscrit leurs
--  fiches dans la base avec le statut « site » : elles sont comptees,
--  mais la page ne les reaffiche pas, puisqu'elle ne lit que celles
--  qui portent le statut « publie ». Leur texte complet et leurs six
--  traductions restent ou ils sont.
--
--  A executer apres asso_compteurs_vivants.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LES TROIS FICHES
-- ---------------------------------------------------------------------
insert into asso_histoires (signature, pays, chapitre, langue, texte, statut)
select v.signature, v.pays, v.chapitre, v.langue, v.texte, 'site'
  from (values
         ('Elisabeth, 56 ans', 'France',    0, 'fr',
          'Histoire ecrite directement dans la page du livre.'),
         ('Caroline, 54 ans',  'Australie', 3, 'en',
          'Histoire ecrite directement dans la page du livre.'),
         ('Méline, 16 ans',    'France',    3, 'fr',
          'Histoire ecrite directement dans la page du livre.')
       ) as v(signature, pays, chapitre, langue, texte)
 where not exists (select 1 from asso_histoires x
                    where x.signature = v.signature and x.statut = 'site');

-- le chiffre a la main n'a plus lieu d'etre
delete from asso_chiffres where cle = 'histoires_livre';


-- ---------------------------------------------------------------------
-- 2. LES COMPTEURS COMPTENT LES DEUX
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

  (select count(*)::int from asso_histoires h
    where h.statut in ('publie', 'site'))                           as histoires,

  (select count(distinct h.pays)::int
     from asso_histoires h
    where h.statut in ('publie', 'site')
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
-- 3. VERIFICATION
-- ---------------------------------------------------------------------
select * from asso_compteurs;
