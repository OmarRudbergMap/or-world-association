-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LE FORMULAIRE D'ADHESION ECRIT ENFIN DANS LA BASE
--  ---------------------------------------------------------------
--  Jusqu'ici le formulaire ne gardait rien. Ce script installe tout
--  ce qu'il faut pour qu'une candidature soit enregistree :
--
--    1. les colonnes qui manquaient dans asso_membres
--    2. la table asso_benevolat (competences et activites)
--    3. le dossier de depot des documents signes
--    4. la fonction asso_inscription, appelee par le site
--    5. le rattachement automatique des adhesions et des dons
--    6. le tableau asso_fiches, pour tout voir d'un coup d'oeil
--
--  Rien n'est efface, rien n'est remplace. Le script peut etre
--  relance autant de fois qu'on veut.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LES COLONNES QUI MANQUAIENT
-- ---------------------------------------------------------------------
alter table asso_membres
  add column if not exists email            text,
  add column if not exists langue           text,
  add column if not exists adresse2         text,
  add column if not exists reseau_x         text,
  add column if not exists facebook         text,
  add column if not exists parent_nom       text,
  add column if not exists parent_email     text,
  add column if not exists statuts          boolean,
  add column if not exists benevole         boolean,
  add column if not exists autre_competence text,
  add column if not exists autre_activite   text;

alter table asso_membres enable row level security;

drop policy if exists "membre lit sa fiche"      on asso_membres;
drop policy if exists "membre ecrit sa fiche"    on asso_membres;
drop policy if exists "membre modifie sa fiche"  on asso_membres;

create policy "membre lit sa fiche"     on asso_membres
  for select to authenticated using (id = auth.uid());
create policy "membre ecrit sa fiche"   on asso_membres
  for insert to authenticated with check (id = auth.uid());
create policy "membre modifie sa fiche" on asso_membres
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());


-- ---------------------------------------------------------------------
-- 2. LE BENEVOLAT
--    Une ligne par membre, une colonne par question : oui, peut, non.
-- ---------------------------------------------------------------------
create table if not exists asso_benevolat (
  membre           uuid primary key references auth.users(id) on delete cascade,
  email            text,
  benevole         boolean default false,
  chanter          text,
  danser           text,
  dessiner         text,
  graphisme        text,
  photo            text,
  video            text,
  instrument       text,
  ecrire           text,
  couture          text,
  autre_competence text,
  act_shooting     text,
  act_concerts     text,
  act_logistique   text,
  act_stands       text,
  act_ateliers     text,
  act_organisation text,
  act_accueil      text,
  act_communication text,
  autre_activite   text,
  cree_le          timestamptz default now(),
  modifie_le       timestamptz default now()
);

alter table asso_benevolat enable row level security;

drop policy if exists "benevolat lecture"  on asso_benevolat;
drop policy if exists "benevolat ecriture" on asso_benevolat;
drop policy if exists "benevolat modif"    on asso_benevolat;

create policy "benevolat lecture"  on asso_benevolat
  for select to authenticated using (membre = auth.uid());
create policy "benevolat ecriture" on asso_benevolat
  for insert to authenticated with check (membre = auth.uid());
create policy "benevolat modif"    on asso_benevolat
  for update to authenticated using (membre = auth.uid()) with check (membre = auth.uid());


-- ---------------------------------------------------------------------
-- 3. LE DOSSIER DES DOCUMENTS SIGNES
--    Autorisation parentale, droit a l'image. Dossier prive : personne
--    ne peut y lire les fichiers des autres.
--    10 Mo par fichier, PDF et images seulement.
-- ---------------------------------------------------------------------
do $dossier$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('documents', 'documents', false, 10485760,
          array['application/pdf','image/jpeg','image/png'])
  on conflict (id) do update
     set public             = false,
         file_size_limit    = 10485760,
         allowed_mime_types = array['application/pdf','image/jpeg','image/png'];
exception when insufficient_privilege then
  raise notice 'Le dossier documents est a creer a la main dans Storage.';
end
$dossier$;

-- Les regles du dossier. Si Supabase refuse de les poser depuis l'editeur
-- SQL, le script continue quand meme et vous previent : il faudra alors
-- les creer a la main dans Storage > Policies.
do $regles$
begin
  drop policy if exists "documents depot"   on storage.objects;
  drop policy if exists "documents lecture" on storage.objects;

  create policy "documents depot" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'documents'
                and (storage.foldername(name))[1] = auth.uid()::text);

  create policy "documents lecture" on storage.objects
    for select to authenticated
    using (bucket_id = 'documents'
           and (storage.foldername(name))[1] = auth.uid()::text);
exception when insufficient_privilege then
  raise notice 'Les regles du dossier documents sont a creer a la main dans Storage > Policies.';
end
$regles$;

alter table asso_documents enable row level security;

drop policy if exists "documents fiche lecture"  on asso_documents;
drop policy if exists "documents fiche ecriture" on asso_documents;

create policy "documents fiche lecture"  on asso_documents
  for select to authenticated using (membre = auth.uid());
create policy "documents fiche ecriture" on asso_documents
  for insert to authenticated with check (membre = auth.uid());


-- ---------------------------------------------------------------------
-- 4. LA FONCTION APPELEE PAR LE SITE
--    Elle n'ecrit que pour le compte qui vient d'etre cree, et
--    seulement si l'adresse donnee est bien celle de ce compte.
-- ---------------------------------------------------------------------
create or replace function asso_inscription(
  p_id        uuid,
  p_email     text,
  p_fiche     jsonb,
  p_benevolat jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text;
  v_numero int;
begin
  select lower(u.email) into v_email from auth.users u where u.id = p_id;
  if v_email is null then
    raise exception 'Compte introuvable.';
  end if;
  if v_email is distinct from lower(trim(p_email)) then
    raise exception 'Cette adresse ne correspond pas au compte.';
  end if;

  -- le numero de membre : celui de son ancienne adhesion s'il en avait
  -- une sur l'ancien site, sinon le premier numero encore libre
  select min(a.numero_membre) into v_numero
    from asso_adhesions a
   where lower(a.email) = v_email
     and a.numero_membre is not null;

  if v_numero is null then
    perform pg_advisory_xact_lock(hashtext('asso_numero_membre'));
    select coalesce(max(t.n), 0) + 1 into v_numero
      from (
        select max(a.numero_membre) as n from asso_adhesions a
        union all
        select max(nullif(regexp_replace(coalesce(m.numero, ''), '[^0-9]', '', 'g'), '')::int)
          from asso_membres m
      ) t;
  end if;

  insert into asso_membres (
    id, email, prenom, nom, pays, langue, date_naissance,
    indicatif, telephone, adresse, adresse2, ville, code_postal,
    instagram, tiktok, reseau_x, facebook,
    mineur, parent_nom, parent_email,
    droit_image, rgpd, reglement, statuts,
    benevole, autre_competence, autre_activite,
    numero, modifie_le
  ) values (
    p_id,
    lower(trim(p_email)),
    nullif(trim(coalesce(p_fiche->>'prenom', '')), ''),
    nullif(trim(coalesce(p_fiche->>'nom', '')), ''),
    nullif(trim(coalesce(p_fiche->>'pays', '')), ''),
    coalesce(nullif(p_fiche->>'langue', ''), 'fr'),
    nullif(p_fiche->>'date_naissance', '')::date,
    nullif(p_fiche->>'indicatif', ''),
    nullif(p_fiche->>'telephone', ''),
    nullif(p_fiche->>'adresse', ''),
    nullif(p_fiche->>'adresse2', ''),
    nullif(p_fiche->>'ville', ''),
    nullif(p_fiche->>'code_postal', ''),
    nullif(p_fiche->>'instagram', ''),
    nullif(p_fiche->>'tiktok', ''),
    nullif(p_fiche->>'x', ''),
    nullif(p_fiche->>'facebook', ''),
    coalesce((p_fiche->>'mineur')::boolean, false),
    nullif(p_fiche->>'parent_nom', ''),
    nullif(p_fiche->>'parent_email', ''),
    coalesce((p_fiche->>'droit_image')::boolean, false),
    coalesce((p_fiche->>'rgpd')::boolean, false),
    coalesce((p_fiche->>'reglement')::boolean, false),
    coalesce((p_fiche->>'statuts')::boolean, false),
    coalesce((p_benevolat->>'benevole')::boolean, false),
    nullif(p_benevolat->>'autre_competence', ''),
    nullif(p_benevolat->>'autre_activite', ''),
    v_numero::text,
    now()
  )
  on conflict (id) do update set
    email            = excluded.email,
    prenom           = coalesce(excluded.prenom,           asso_membres.prenom),
    nom              = coalesce(excluded.nom,              asso_membres.nom),
    pays             = coalesce(excluded.pays,             asso_membres.pays),
    langue           = coalesce(excluded.langue,           asso_membres.langue),
    date_naissance   = coalesce(excluded.date_naissance,   asso_membres.date_naissance),
    indicatif        = coalesce(excluded.indicatif,        asso_membres.indicatif),
    telephone        = coalesce(excluded.telephone,        asso_membres.telephone),
    adresse          = coalesce(excluded.adresse,          asso_membres.adresse),
    adresse2         = coalesce(excluded.adresse2,         asso_membres.adresse2),
    ville            = coalesce(excluded.ville,            asso_membres.ville),
    code_postal      = coalesce(excluded.code_postal,      asso_membres.code_postal),
    instagram        = coalesce(excluded.instagram,        asso_membres.instagram),
    tiktok           = coalesce(excluded.tiktok,           asso_membres.tiktok),
    reseau_x         = coalesce(excluded.reseau_x,         asso_membres.reseau_x),
    facebook         = coalesce(excluded.facebook,         asso_membres.facebook),
    mineur           = excluded.mineur,
    parent_nom       = coalesce(excluded.parent_nom,       asso_membres.parent_nom),
    parent_email     = coalesce(excluded.parent_email,     asso_membres.parent_email),
    droit_image      = excluded.droit_image,
    rgpd             = excluded.rgpd,
    reglement        = excluded.reglement,
    statuts          = excluded.statuts,
    benevole         = excluded.benevole,
    autre_competence = coalesce(excluded.autre_competence, asso_membres.autre_competence),
    autre_activite   = coalesce(excluded.autre_activite,   asso_membres.autre_activite),
    numero           = coalesce(asso_membres.numero,       excluded.numero),
    modifie_le       = now();

  -- le numero finalement retenu
  select nullif(regexp_replace(coalesce(m.numero, ''), '[^0-9]', '', 'g'), '')::int
    into v_numero
    from asso_membres m where m.id = p_id;

  insert into asso_benevolat (
    membre, email, benevole,
    chanter, danser, dessiner, graphisme, photo, video, instrument,
    ecrire, couture, autre_competence,
    act_shooting, act_concerts, act_logistique, act_stands,
    act_ateliers, act_organisation, act_accueil, act_communication,
    autre_activite, modifie_le
  ) values (
    p_id, lower(trim(p_email)),
    coalesce((p_benevolat->>'benevole')::boolean, false),
    p_benevolat->>'chanter',    p_benevolat->>'danser',
    p_benevolat->>'dessiner',   p_benevolat->>'graphisme',
    p_benevolat->>'photo',      p_benevolat->>'video',
    p_benevolat->>'instrument', p_benevolat->>'ecrire',
    p_benevolat->>'couture',    nullif(p_benevolat->>'autre_competence', ''),
    p_benevolat->>'act_shooting',     p_benevolat->>'act_concerts',
    p_benevolat->>'act_logistique',   p_benevolat->>'act_stands',
    p_benevolat->>'act_ateliers',     p_benevolat->>'act_organisation',
    p_benevolat->>'act_accueil',      p_benevolat->>'act_communication',
    nullif(p_benevolat->>'autre_activite', ''),
    now()
  )
  on conflict (membre) do update set
    email             = excluded.email,
    benevole          = excluded.benevole,
    chanter           = excluded.chanter,
    danser            = excluded.danser,
    dessiner          = excluded.dessiner,
    graphisme         = excluded.graphisme,
    photo             = excluded.photo,
    video             = excluded.video,
    instrument        = excluded.instrument,
    ecrire            = excluded.ecrire,
    couture           = excluded.couture,
    autre_competence  = excluded.autre_competence,
    act_shooting      = excluded.act_shooting,
    act_concerts      = excluded.act_concerts,
    act_logistique    = excluded.act_logistique,
    act_stands        = excluded.act_stands,
    act_ateliers      = excluded.act_ateliers,
    act_organisation  = excluded.act_organisation,
    act_accueil       = excluded.act_accueil,
    act_communication = excluded.act_communication,
    autre_activite    = excluded.autre_activite,
    modifie_le        = now();

  -- on rattache tout de suite ses anciennes adhesions et ses anciens dons
  update asso_adhesions a set membre = p_id
   where a.membre is null and lower(a.email) = v_email;
  update asso_dons d set membre = p_id
   where d.membre is null and lower(d.email) = v_email;

  return jsonb_build_object('ok', true, 'numero', v_numero);
end;
$$;

revoke all on function asso_inscription(uuid, text, jsonb, jsonb) from public;
grant execute on function asso_inscription(uuid, text, jsonb, jsonb) to anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. LE RATTACHEMENT AUTOMATIQUE
--    Quand Stripe cree une adhesion ou un don, on cherche le compte
--    qui porte la meme adresse et on l'y accroche tout de suite.
-- ---------------------------------------------------------------------
create or replace function asso_rattacher_au_compte()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.membre is null and new.email is not null then
    select u.id into new.membre
      from auth.users u
     where lower(u.email) = lower(new.email)
     limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists asso_adhesions_rattacher on asso_adhesions;
create trigger asso_adhesions_rattacher
  before insert on asso_adhesions
  for each row execute function asso_rattacher_au_compte();

drop trigger if exists asso_dons_rattacher on asso_dons;
create trigger asso_dons_rattacher
  before insert on asso_dons
  for each row execute function asso_rattacher_au_compte();


-- ---------------------------------------------------------------------
-- 6. LE TABLEAU DE BORD DES FICHES
--    Tout ce qu'on sait d'une personne sur une seule ligne.
--    Reserve a vous : ni anon ni authenticated n'y ont acces.
-- ---------------------------------------------------------------------
create or replace view asso_fiches as
  select m.numero,
         m.prenom, m.nom, m.email, m.pays, m.langue,
         m.date_naissance                          as naissance,
         coalesce(m.indicatif, '') || ' ' || coalesce(m.telephone, '') as telephone,
         coalesce(m.adresse, '')
           || case when m.adresse2 is null then '' else ', ' || m.adresse2 end
           || ', ' || coalesce(m.code_postal, '') || ' ' || coalesce(m.ville, '')
                                                    as adresse_postale,
         m.instagram, m.tiktok, m.reseau_x, m.facebook,
         m.mineur, m.parent_nom, m.parent_email,
         m.droit_image, m.rgpd, m.reglement, m.statuts,
         m.benevole,
         a.date_debut                               as adhesion_debut,
         a.date_fin                                 as adhesion_fin,
         (a.date_fin >= current_date)               as a_jour,
         a.montant, a.numero_recu,
         (select coalesce(sum(d.montant), 0) from asso_dons d
           where d.membre = m.id
             and coalesce(d.statut, 'valide') <> 'essai')  as dons,
         m.cree_le                                  as inscrit_le
    from asso_membres m
    left join lateral (
      select * from asso_adhesions x
       where x.membre = m.id
       order by x.date_fin desc nulls last
       limit 1
    ) a on true
   order by m.cree_le;

revoke all on asso_fiches from anon, authenticated;


-- ---------------------------------------------------------------------
-- 7. VERIFICATION
-- ---------------------------------------------------------------------
select 'asso_membres'   as table_, count(*) as lignes from asso_membres
union all
select 'asso_benevolat',      count(*) from asso_benevolat
union all
select 'asso_documents',      count(*) from asso_documents
union all
select 'asso_adhesions',      count(*) from asso_adhesions
union all
select 'asso_dons',           count(*) from asso_dons;
