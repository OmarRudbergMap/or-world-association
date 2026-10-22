-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  REPARER LA CREATION DE COMPTE
--
--  Deux programmes se declenchent a chaque inscription. Le second
--  plantait des que l'adresse figurait parmi les pre-inscrits, et
--  Supabase annulait alors toute l'inscription. Autrement dit, les
--  adherents repris de l'ancien site, c'est-a-dire les premiers a
--  vouloir un compte, etaient les seuls a ne pas pouvoir en creer.
--
--  Ce script corrige la cause, et met les deux programmes a l'abri :
--  desormais, s'ils echouent, ils le notent dans un journal et
--  laissent l'inscription se terminer. Creer un compte ne doit jamais
--  dependre de la reussite de ce qui vient apres.
--
--  Ce script ne supprime rien et peut etre passe plusieurs fois.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. Le journal des incidents.
--     Rien ne se perd en silence : ce qui echoue est ecrit ici.
-- ---------------------------------------------------------------------
create table if not exists asso_incidents (
  id       bigserial primary key,
  quand    timestamptz not null default now(),
  ou       text,
  details  text,
  contexte text
);

alter table asso_incidents enable row level security;


-- ---------------------------------------------------------------------
--  2. A la creation d'un compte : la fiche du membre, et le
--     rattachement de ses adhesions et de ses dons.
-- ---------------------------------------------------------------------
create or replace function public.asso_nouveau_compte()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_mail   text := lower(coalesce(new.email, ''));
  v_prenom text;
  v_nom    text;
  v_numero int;
begin
  if v_mail = '' then return new; end if;

  v_prenom := nullif(trim(coalesce(new.raw_user_meta_data->>'prenom', '')), '');
  v_nom    := nullif(trim(coalesce(new.raw_user_meta_data->>'nom', '')), '');

  if v_prenom is null and v_nom is null then
    select a.prenom, a.nom into v_prenom, v_nom
      from asso_adhesions a
     where lower(a.email) = v_mail
     order by a.date_debut
     limit 1;
  end if;

  insert into asso_membres (id, email, prenom, nom)
  values (new.id, v_mail, v_prenom, v_nom)
  on conflict (id) do update
     set email  = coalesce(asso_membres.email,  excluded.email),
         prenom = coalesce(asso_membres.prenom, excluded.prenom),
         nom    = coalesce(asso_membres.nom,    excluded.nom);

  update asso_adhesions a set membre = new.id
   where a.membre is null and lower(a.email) = v_mail;
  update asso_dons d set membre = new.id
   where d.membre is null and lower(d.email) = v_mail;

  select min(a.numero_membre) into v_numero
    from asso_adhesions a
   where a.membre = new.id and a.numero_membre is not null;

  if v_numero is not null then
    update asso_membres m set numero = v_numero::text
     where m.id = new.id and m.numero is null;
  end if;

  return new;

exception when others then
  -- l'inscription continue, quoi qu'il arrive
  begin
    insert into asso_incidents (ou, details, contexte)
    values ('asso_nouveau_compte', sqlerrm, v_mail);
  exception when others then null;
  end;
  return new;
end;
$function$;


-- ---------------------------------------------------------------------
--  3. Reprendre une personne pre-inscrite sur l'ancien site.
--
--     La correction tient en une ligne : « on conflict (membre, annee) »
--     exigeait une contrainte d'unicite qui n'existe pas sur la table
--     des adhesions. On verifie donc nous-memes, avant d'ecrire.
-- ---------------------------------------------------------------------
create or replace function public.asso_rattacher_preinscrit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  p asso_preinscrits%rowtype;
begin
  select * into p from asso_preinscrits where lower(email) = lower(new.email);

  if found then
    insert into asso_membres
      (id, numero, prenom, nom, date_naissance, telephone, adresse, code_postal, ville, pays,
       instagram, tiktok, mineur, droit_image, rgpd, reglement, benevolat)
    values
      (new.id, p.numero, p.prenom, p.nom, p.date_naissance, p.telephone, p.adresse,
       p.code_postal, p.ville, p.pays, p.instagram, p.tiktok, p.mineur, p.droit_image,
       p.rgpd, p.reglement,
       jsonb_build_object('benevole', p.benevole, 'competences', p.competences,
                          'activites', p.activites))
    on conflict (id) do nothing;

    if not exists (select 1 from asso_adhesions a
                    where a.membre = new.id and a.annee = 2026) then
      insert into asso_adhesions (membre, annee, montant, don, statut, paye_le, reference)
      values (new.id, 2026, p.cotisation, p.don, 'payee', p.date_adhesion, p.commande);
    end if;

    update asso_preinscrits set recupere = true where id = p.id;
  end if;

  return new;

exception when others then
  begin
    insert into asso_incidents (ou, details, contexte)
    values ('asso_rattacher_preinscrit', sqlerrm, lower(coalesce(new.email, '')));
  exception when others then null;
  end;
  return new;
end;
$function$;


-- ---------------------------------------------------------------------
--  4. Voir les incidents depuis la page de moderation.
-- ---------------------------------------------------------------------
create or replace function asso_incidents_recents()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when asso_est_admin()
         then coalesce((select jsonb_agg(x order by x->>'quand' desc)
                          from (select jsonb_build_object(
                                  'quand', i.quand, 'ou', i.ou,
                                  'details', i.details, 'contexte', i.contexte) as x
                                  from asso_incidents i
                                 order by i.quand desc
                                 limit 50) t), '[]'::jsonb)
         else jsonb_build_object('erreur', 'reserve') end;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_incidents_recents() to authenticated';
  end if;
end $$;
