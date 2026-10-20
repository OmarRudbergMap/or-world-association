-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES ANCIENS ADHERENTS RETROUVENT LEUR CARTE
--  ---------------------------------------------------------------
--  Le probleme : jusqu'ici, la fiche d'un membre n'etait creee que si
--  la session s'ouvrait au moment de l'inscription. Quand Supabase
--  demande de confirmer l'adresse par mail, ce n'est pas le cas : la
--  personne confirme, se connecte, et se retrouve sans fiche et sans
--  carte, alors que son adhesion existe bien dans la base.
--
--  La solution : des qu'un compte est cree, quelle que soit la page
--  par laquelle il passe, sa fiche est creee et ses adhesions et ses
--  dons viennent s'y accrocher tout seuls, avec le bon numero de
--  membre, celui de sa premiere adhesion.
--
--  Le script repare aussi les comptes deja crees.
--  Relancable autant de fois qu'on veut.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. A LA CREATION DU COMPTE
-- ---------------------------------------------------------------------
create or replace function asso_nouveau_compte()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mail   text := lower(coalesce(new.email, ''));
  v_prenom text;
  v_nom    text;
  v_numero int;
begin
  if v_mail = '' then return new; end if;

  -- le prenom et le nom tels que la personne les a donnes a l'inscription
  v_prenom := nullif(trim(coalesce(new.raw_user_meta_data->>'prenom', '')), '');
  v_nom    := nullif(trim(coalesce(new.raw_user_meta_data->>'nom', '')), '');

  -- a defaut, ceux de son adhesion
  if v_prenom is null and v_nom is null then
    select a.prenom, a.nom into v_prenom, v_nom
      from asso_adhesions a
     where lower(a.email) = v_mail
     order by a.date_debut
     limit 1;
  end if;

  -- la fiche. Son insertion declenche asso_rattacher_tout, qui accroche
  -- les adhesions et les dons portant la meme adresse.
  insert into asso_membres (id, email, prenom, nom)
  values (new.id, v_mail, v_prenom, v_nom)
  on conflict (id) do update
     set email  = coalesce(asso_membres.email,  excluded.email),
         prenom = coalesce(asso_membres.prenom, excluded.prenom),
         nom    = coalesce(asso_membres.nom,    excluded.nom);

  -- par securite, si la fiche existait deja le declencheur n'a pas joue
  update asso_adhesions a set membre = new.id
   where a.membre is null and lower(a.email) = v_mail;
  update asso_dons d set membre = new.id
   where d.membre is null and lower(d.email) = v_mail;

  -- son numero de membre : celui de sa premiere adhesion
  select min(a.numero_membre) into v_numero
    from asso_adhesions a
   where a.membre = new.id and a.numero_membre is not null;

  if v_numero is not null then
    update asso_membres m set numero = v_numero::text
     where m.id = new.id and m.numero is null;
  end if;

  return new;
end;
$$;

drop trigger if exists asso_auth_nouveau on auth.users;
create trigger asso_auth_nouveau
  after insert on auth.users
  for each row execute function asso_nouveau_compte();


-- ---------------------------------------------------------------------
-- 2. REPARER LES COMPTES DEJA CREES
-- ---------------------------------------------------------------------

-- la fiche manquante
insert into asso_membres (id, email, prenom, nom)
select u.id,
       lower(u.email),
       nullif(trim(coalesce(u.raw_user_meta_data->>'prenom', '')), ''),
       nullif(trim(coalesce(u.raw_user_meta_data->>'nom', '')), '')
  from auth.users u
 where u.email is not null
   and not exists (select 1 from asso_membres m where m.id = u.id)
on conflict (id) do nothing;

-- l'adresse, quand la fiche avait ete creee sans
update asso_membres m
   set email = lower(u.email)
  from auth.users u
 where u.id = m.id and m.email is null;

-- le rattachement
update asso_adhesions a
   set membre = u.id
  from auth.users u
 where a.membre is null and a.email is not null
   and lower(a.email) = lower(u.email);

update asso_dons d
   set membre = u.id
  from auth.users u
 where d.membre is null and d.email is not null
   and lower(d.email) = lower(u.email);

-- le prenom et le nom, repris de l'adhesion quand ils manquent
update asso_membres m
   set prenom = coalesce(m.prenom, a.prenom),
       nom    = coalesce(m.nom,    a.nom)
  from asso_adhesions a
 where a.membre = m.id
   and (m.prenom is null or m.nom is null);

-- le numero de membre
update asso_membres m
   set numero = x.n::text
  from (select a.membre as id, min(a.numero_membre) as n
          from asso_adhesions a
         where a.membre is not null and a.numero_membre is not null
         group by a.membre) x
 where x.id = m.id and m.numero is null;


-- ---------------------------------------------------------------------
-- 3. QUI DOIT ENCORE CREER SON COMPTE
--    La liste a envoyer : ces personnes ont paye, leur adhesion est
--    dans la base, il ne leur manque que le compte du site.
-- ---------------------------------------------------------------------
create or replace view asso_a_inscrire as
  select a.numero_membre as numero,
         a.prenom, a.nom, a.email, a.pays, a.langue,
         a.date_debut, a.date_fin,
         (a.date_fin >= current_date) as a_jour
    from asso_adhesions a
   where a.membre is null
     and a.email is not null
     and coalesce(a.statut, 'actif') <> 'essai'
     and not exists (select 1 from auth.users u where lower(u.email) = lower(a.email))
   order by a.numero_membre;

revoke all on asso_a_inscrire from anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. VERIFICATION
-- ---------------------------------------------------------------------
select * from asso_a_inscrire;
