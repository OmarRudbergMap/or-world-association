-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LE NUMERO DE MEMBRE, POUR LA CARTE
--  ---------------------------------------------------------------
--  Le numero est attribue une fois pour toutes, dans l'ordre des
--  premieres adhesions. Il suit la personne, pas l'annee : en
--  renouvelant, elle garde le meme numero.
--  A executer apres asso_adhesions_dates.sql.
-- =====================================================================

alter table asso_adhesions
  add column if not exists numero_membre int;

create index if not exists asso_adhesions_numero on asso_adhesions (numero_membre);


-- ---------------------------------------------------------------------
-- La fonction : si la personne a deja un numero, on le rend ; sinon on
-- lui en attribue un nouveau, le suivant dans la suite.
-- ---------------------------------------------------------------------
create or replace function asso_numero_membre(p_email text)
returns int
language plpgsql
as $$
declare n int;
begin
  if p_email is null then return null; end if;
  perform pg_advisory_xact_lock(hashtext('numero_membre'));

  select numero_membre into n
    from asso_adhesions
   where lower(email) = lower(p_email) and numero_membre is not null
   limit 1;
  if n is not null then return n; end if;

  select coalesce(max(numero_membre), 0) + 1 into n from asso_adhesions;
  return n;
end;
$$;


-- ---------------------------------------------------------------------
-- On attribue leur numero aux adhesions deja enregistrees, dans l'ordre
-- des dates de debut. Elisabeth, la premiere, recoit le numero 1.
-- ---------------------------------------------------------------------
with ordre as (
  select lower(email) as e,
         row_number() over (order by min(date_debut), min(id)) as n
    from asso_adhesions
   where email is not null
   group by lower(email)
)
update asso_adhesions a
   set numero_membre = o.n
  from ordre o
 where lower(a.email) = o.e
   and a.numero_membre is null;


-- ---------------------------------------------------------------------
-- Desormais, toute nouvelle adhesion recoit son numero toute seule.
-- ---------------------------------------------------------------------
create or replace function asso_poser_numero()
returns trigger
language plpgsql
as $$
begin
  if new.numero_membre is null then
    new.numero_membre := asso_numero_membre(new.email);
  end if;
  return new;
end;
$$;

drop trigger if exists asso_numero on asso_adhesions;
create trigger asso_numero
  before insert on asso_adhesions
  for each row execute function asso_poser_numero();


-- ---------------------------------------------------------------------
-- Verification : vos 11 adherents avec leur numero
-- ---------------------------------------------------------------------
select numero_membre, prenom, nom, pays, date_debut, date_fin, numero_recu
  from asso_adhesions
 order by numero_membre;
