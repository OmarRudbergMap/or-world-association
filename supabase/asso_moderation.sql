-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LA MODERATION : tout ce qui attend une decision, au meme endroit.
--
--  Ce script ne supprime rien. Il peut etre passe plusieurs fois.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. Qui a le droit de moderer.
--     On designe par adresse e-mail, et non par compte : ainsi le
--     droit existe meme avant que la personne ait cree son compte.
-- ---------------------------------------------------------------------
create table if not exists asso_admins (
  email   text primary key,
  nom     text,
  ajoute_le timestamptz not null default now()
);

alter table asso_admins enable row level security;

insert into asso_admins (email, nom)
values ('elisabeth.sikora@orange.fr', 'Elisabeth Sikora')
on conflict (email) do nothing;


-- ---------------------------------------------------------------------
--  2. La personne connectee est-elle moderatrice ?
-- ---------------------------------------------------------------------
create or replace function asso_est_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from asso_admins a
     where lower(a.email) = lower(coalesce(
             (select u.email from auth.users u where u.id = auth.uid()),
             ''))
  );
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_est_admin() to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  3. Tout ce qui attend une decision.
--     Une seule liste, triee du plus ancien au plus recent : ce qui
--     attend depuis le plus longtemps passe devant.
-- ---------------------------------------------------------------------
create or replace function asso_moderation()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tout jsonb := '[]'::jsonb;
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  -- les pages du livre collaboratif
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb)
    into v_tout
  from (
    select jsonb_build_object(
      'source', 'histoire', 'id', h.id, 'date', h.cree_le,
      'titre', coalesce(nullif(h.signature, ''), h.pseudo, '—'),
      'detail', 'Chapitre ' || (coalesce(h.chapitre, 0) + 1) ||
                coalesce(' · ' || nullif(h.pays, ''), ''),
      'extrait', left(coalesce(h.texte, ''), 600),
      'lien', null) as x
      from asso_histoires h
     where h.statut in ('en attente', 'en_attente')
  ) t;

  -- les videos du flashmob
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb)
    into v_tout
  from (
    select jsonb_build_object(
      'source', 'video', 'id', v.id, 'date', v.cree_le,
      'titre', coalesce(nullif(v.pseudo, ''), '—'),
      'detail', 'Chapitre ' || coalesce(v.chapitre::text, '?') ||
                coalesce(' · ' || nullif(v.reseau, ''), ''),
      'extrait', null,
      'lien', v.lien) as x
      from asso_videos v
     where v.statut in ('en attente', 'en_attente')
  ) t;

  -- les recits de concert
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb)
    into v_tout
  from (
    select jsonb_build_object(
      'source', 'recit', 'id', r.id, 'date', r.cree_le,
      'titre', coalesce(nullif(r.signature, ''), '—'),
      'detail', coalesce(nullif(r.concert, ''), ''),
      'extrait', left(coalesce(r.recit, ''), 600),
      'lien', null) as x
      from asso_recits r
     where r.statut in ('en attente', 'en_attente')
  ) t;

  -- les articles de presse signales
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb)
    into v_tout
  from (
    select jsonb_build_object(
      'source', 'presse', 'id', p.id, 'date', p.cree_le,
      'titre', coalesce(nullif(p.media, ''), '—'),
      'detail', coalesce(p.date_parution::text, ''),
      'extrait', null,
      'lien', p.lien) as x
      from asso_presse_signalee p
     where p.statut in ('en attente', 'en_attente')
  ) t;

  -- les rendez-vous proposes pour le flashmob
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb)
    into v_tout
  from (
    select jsonb_build_object(
      'source', 'rdv', 'id', d.id, 'date', d.cree_le,
      'titre', coalesce(nullif(d.pseudo, ''), '—'),
      'detail', concat_ws(' · ', nullif(d.ville, ''), nullif(d.pays, ''),
                          nullif(d.lieu, ''), d.jour::text, d.heure::text),
      'extrait', nullif(d.mot, ''),
      'lien', null) as x
      from asso_rdv d
     where d.statut in ('en attente', 'en_attente')
  ) t;

  return jsonb_build_object('liste', v_tout);
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_moderation() to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  4. Publier ou refuser.
--     Rien n'est jamais supprime : une decision ne fait que changer
--     la mention portee par la ligne.
-- ---------------------------------------------------------------------
create or replace function asso_moderer(
  p_source   text,
  p_id       bigint,
  p_decision text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
  v_n      int := 0;
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  if p_decision = 'publier' then
    v_statut := 'publie';
  elsif p_decision = 'refuser' then
    v_statut := 'refuse';
  else
    return jsonb_build_object('erreur', 'decision inconnue');
  end if;

  if    p_source = 'histoire' then
    update asso_histoires       set statut = v_statut where id = p_id;
  elsif p_source = 'video'    then
    update asso_videos          set statut = v_statut where id = p_id;
  elsif p_source = 'recit'    then
    update asso_recits          set statut = v_statut where id = p_id;
  elsif p_source = 'presse'   then
    update asso_presse_signalee set statut = v_statut where id = p_id;
  elsif p_source = 'rdv'      then
    update asso_rdv             set statut = v_statut where id = p_id;
  else
    return jsonb_build_object('erreur', 'source inconnue');
  end if;

  get diagnostics v_n = row_count;
  return jsonb_build_object('statut', v_statut, 'lignes', v_n);
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_moderer(text, bigint, text) to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  5. Le brouillon d'une page du livre.
--     Une personne connectee peut commencer son texte sur son
--     telephone et le finir sur son ordinateur : le brouillon la suit.
--     Chacun ne voit que le sien.
-- ---------------------------------------------------------------------
create table if not exists asso_brouillons (
  membre      uuid primary key,
  pseudo      text,
  pays        text,
  chapitre    int,
  texte       text,
  publication boolean default false,
  relecture   boolean default false,
  mineur      boolean default false,
  modifie_le  timestamptz not null default now()
);

alter table asso_brouillons enable row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated')
     and not exists (select 1 from pg_policies
                      where tablename = 'asso_brouillons'
                        and policyname = 'mon brouillon') then
    execute 'create policy "mon brouillon" on asso_brouillons
               for all to authenticated
               using (membre = auth.uid())
               with check (membre = auth.uid())';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant select, insert, update, delete on asso_brouillons to authenticated';
  end if;
end $$;
