-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES DONS SUR LA FICHE DU MEMBRE
--  ---------------------------------------------------------------
--  Un don est rattache a la personne par son adresse e-mail, comme les
--  adhesions, et apparait dans son espace. Chacun ne voit que les siens.
--  A executer apres asso_paiements_stripe.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LE LIEN AVEC LE COMPTE
-- ---------------------------------------------------------------------
alter table asso_dons
  add column if not exists membre     uuid references auth.users(id) on delete set null,
  add column if not exists fait_le    date,
  add column if not exists origine    text;

create index if not exists asso_dons_membre on asso_dons (membre);
create index if not exists asso_dons_email  on asso_dons (lower(email));

-- la date du don : pour ceux qui arrivent par Stripe, c'est le jour meme
update asso_dons set fait_le = cree_le::date where fait_le is null;


-- ---------------------------------------------------------------------
-- 2. LE RATTACHEMENT AUTOMATIQUE, COMME POUR LES ADHESIONS
-- ---------------------------------------------------------------------
create or replace function asso_rattacher_tout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update asso_adhesions a
     set membre = new.id
    from auth.users u
   where u.id = new.id and a.membre is null and a.email is not null
     and lower(a.email) = lower(u.email);

  update asso_dons d
     set membre = new.id
    from auth.users u
   where u.id = new.id and d.membre is null and d.email is not null
     and lower(d.email) = lower(u.email);
  return new;
end;
$$;

drop trigger if exists asso_rattacher on asso_membres;
create trigger asso_rattacher
  after insert on asso_membres
  for each row execute function asso_rattacher_tout();

-- on rattache tout de suite ceux dont le compte existe deja
update asso_dons d
   set membre = u.id
  from auth.users u
 where d.membre is null and d.email is not null
   and lower(d.email) = lower(u.email);


-- ---------------------------------------------------------------------
-- 3. CHACUN NE VOIT QUE SES DONS
-- ---------------------------------------------------------------------
alter table asso_dons enable row level security;

drop policy if exists "don lisible par son auteur" on asso_dons;
create policy "don lisible par son auteur"
  on asso_dons for select
  using (membre = auth.uid());


-- ---------------------------------------------------------------------
-- 4. LE TOTAL DES DONS, POUR LE COMPTEUR PUBLIC
--    Aucun nom, aucune adresse, juste un nombre et une somme.
-- ---------------------------------------------------------------------
create or replace view asso_dons_total as
  select count(*)::int as nombre,
         coalesce(sum(montant), 0)::numeric(10,2) as somme
    from asso_dons;

grant select on asso_dons_total to anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. REPRENDRE LES DONS DEJA FAITS
--    Completez le tableau ci-dessous avec les dons passes, puis
--    relancez cette partie. Elle ne double rien : un meme don, meme
--    adresse et meme date, n'est insere qu'une fois.
--    Le numero de recu est attribue dans l'ordre des dates.
-- ---------------------------------------------------------------------
create unique index if not exists asso_dons_unique_ancien
  on asso_dons (lower(email), fait_le, montant)
  where stripe_session is null;

-- EXEMPLE, a remplacer par vos vraies lignes :
--
-- insert into asso_dons (email, prenom, nom, pays, montant, moyen, fait_le, origine)
-- values
--   ('adresse@exemple.fr', 'Prenom', 'Nom', 'France', 20.00, 'ancien site', date '2026-02-14', 'reprise'),
--   ('autre@exemple.fr',   'Prenom', 'Nom', 'Suède',  10.00, 'ancien site', date '2026-03-02', 'reprise')
-- on conflict do nothing;
--
-- puis, pour leur donner leur numero de recu dans l'ordre :
--
-- with ordre as (
--   select id, 'DON-' || extract(year from fait_le)::text || '-' ||
--          lpad(row_number() over (order by fait_le, id)::text, 3, '0') as num
--     from asso_dons where numero_recu is null
-- )
-- update asso_dons d set numero_recu = o.num from ordre o where d.id = o.id;


-- ---------------------------------------------------------------------
-- 6. VERIFICATION
-- ---------------------------------------------------------------------
select numero_recu, prenom, nom, email, montant, fait_le, moyen, origine
  from asso_dons
 order by fait_le, id;
