-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES QUATRE FORMULAIRES QUI NE MENAIENT NULLE PART
--
--    · Blog        : proposer un sujet d'article
--    · Blog        : s'inscrire aux nouvelles
--    · Radio Day   : proposer une radio a ajouter
--    · Young Royals: envoyer son analyse d'un episode
--
--  Les trois premiers passent par votre moderation. Les inscriptions
--  aux nouvelles, elles, ne se publient pas : elles forment une liste,
--  que vous retrouverez dans votre page Moderation.
--
--  A PASSER EN DERNIER : ce script reecrit la file de moderation avec
--  toutes ses sources, le mur des radios compris.
--
--  Ce script ne supprime rien et peut etre passe plusieurs fois.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. PROPOSER UN SUJET D'ARTICLE
-- ---------------------------------------------------------------------
create table if not exists asso_sujets (
  id       bigserial primary key,
  titre    text not null,
  rubrique text,
  texte    text not null,
  pseudo   text,
  email    text,
  langue   text,
  membre   uuid,
  statut   text not null default 'en attente',
  cree_le  timestamptz not null default now()
);
alter table asso_sujets enable row level security;


-- ---------------------------------------------------------------------
--  2. S'INSCRIRE AUX NOUVELLES
--     Le consentement est horodate : c'est ce que demande le RGPD.
-- ---------------------------------------------------------------------
create table if not exists asso_abonnes (
  id          bigserial primary key,
  email       text not null,
  langue      text,
  consenti_le timestamptz not null default now(),
  desinscrit  boolean not null default false,
  cree_le     timestamptz not null default now()
);
create unique index if not exists asso_abonnes_mail
  on asso_abonnes (lower(email));
alter table asso_abonnes enable row level security;


-- ---------------------------------------------------------------------
--  3. PROPOSER UNE RADIO
-- ---------------------------------------------------------------------
create table if not exists asso_radios_proposees (
  id        bigserial primary key,
  nom       text not null,
  pays      text,
  instagram text,
  lien      text,
  langue    text,
  membre    uuid,
  statut    text not null default 'en attente',
  cree_le   timestamptz not null default now()
);
alter table asso_radios_proposees enable row level security;


-- ---------------------------------------------------------------------
--  4. ENVOYER SON ANALYSE D'UN EPISODE
-- ---------------------------------------------------------------------
create table if not exists asso_analyses (
  id       bigserial primary key,
  episode  text,
  signature text,
  texte    text not null,
  langue   text,
  membre   uuid,
  statut   text not null default 'en attente',
  cree_le  timestamptz not null default now()
);
alter table asso_analyses enable row level security;


-- ---------------------------------------------------------------------
--  Qui a le droit de quoi.
--  Deposer : tout le monde. Relire : seulement ce qui est publie,
--  et pour les abonnes, personne : la liste reste privee.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['asso_sujets', 'asso_radios_proposees', 'asso_analyses'] loop
    if not exists (select 1 from pg_policies where tablename = t and policyname = 'deposer') then
      execute format('create policy "deposer" on %I for insert to anon, authenticated
                        with check (statut = ''en attente'')', t);
    end if;
    if not exists (select 1 from pg_policies where tablename = t and policyname = 'lire le publie') then
      execute format('create policy "lire le publie" on %I for select to anon, authenticated
                        using (statut = ''publie'')', t);
    end if;
    execute format('grant select, insert on %I to anon, authenticated', t);
    execute format('grant usage, select on sequence %I to anon, authenticated', t || '_id_seq');
  end loop;

  if not exists (select 1 from pg_policies where tablename = 'asso_abonnes' and policyname = 'sinscrire') then
    execute 'create policy "sinscrire" on asso_abonnes for insert to anon, authenticated with check (true)';
  end if;
  execute 'grant insert on asso_abonnes to anon, authenticated';
  execute 'grant usage, select on sequence asso_abonnes_id_seq to anon, authenticated';
end $$;


-- ---------------------------------------------------------------------
--  LA FILE DE MODERATION, AU COMPLET
--  Neuf sources desormais. Triee du plus ancien au plus recent.
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

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','histoire','id',h.id,'date',h.cree_le,
      'titre', coalesce(nullif(h.signature,''), h.pseudo, '—'),
      'detail', 'Chapitre ' || (coalesce(h.chapitre,0)+1) || coalesce(' · ' || nullif(h.pays,''), ''),
      'extrait', left(coalesce(h.texte,''), 600), 'lien', null) as x
    from asso_histoires h where h.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','video','id',v.id,'date',v.cree_le,
      'titre', coalesce(nullif(v.pseudo,''), '—'),
      'detail', 'Chapitre ' || coalesce(v.chapitre::text,'?') || coalesce(' · ' || nullif(v.reseau,''), ''),
      'extrait', null, 'lien', v.lien) as x
    from asso_videos v where v.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','recit','id',r.id,'date',r.cree_le,
      'titre', coalesce(nullif(r.signature,''), '—'),
      'detail', coalesce(nullif(r.concert,''), ''),
      'extrait', left(coalesce(r.recit,''), 600), 'lien', null) as x
    from asso_recits r where r.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','presse','id',p.id,'date',p.cree_le,
      'titre', coalesce(nullif(p.media,''), '—'),
      'detail', coalesce(p.date_parution::text, ''),
      'extrait', null, 'lien', p.lien) as x
    from asso_presse_signalee p where p.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','rdv','id',d.id,'date',d.cree_le,
      'titre', coalesce(nullif(d.pseudo,''), '—'),
      'detail', concat_ws(' · ', nullif(d.ville,''), nullif(d.pays,''),
                          nullif(d.lieu,''), d.jour::text, d.heure::text),
      'extrait', nullif(d.mot,''), 'lien', null) as x
    from asso_rdv d where d.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','mur','id',m.id,'date',m.cree_le,
      'titre', coalesce(nullif(m.pseudo,''), '—'),
      'detail', concat_ws(' · ', nullif(m.radio,''), nullif(m.pays,'')),
      'extrait', left(coalesce(m.message,''), 600), 'lien', null) as x
    from asso_mur_radios m where m.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','sujet','id',s.id,'date',s.cree_le,
      'titre', coalesce(nullif(s.titre,''), '—'),
      'detail', concat_ws(' · ', nullif(s.rubrique,''), nullif(s.pseudo,'')),
      'extrait', left(coalesce(s.texte,''), 600), 'lien', null) as x
    from asso_sujets s where s.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','radio','id',r.id,'date',r.cree_le,
      'titre', coalesce(nullif(r.nom,''), '—'),
      'detail', concat_ws(' · ', nullif(r.pays,''),
                          case when nullif(r.instagram,'') is not null
                               then '@' || r.instagram end),
      'extrait', null, 'lien', nullif(r.lien,'')) as x
    from asso_radios_proposees r where r.statut in ('en attente','en_attente')) t;

  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','analyse','id',a.id,'date',a.cree_le,
      'titre', coalesce(nullif(a.signature,''), '—'),
      'detail', coalesce(nullif(a.episode,''), ''),
      'extrait', left(coalesce(a.texte,''), 600), 'lien', null) as x
    from asso_analyses a where a.statut in ('en attente','en_attente')) t;

  return jsonb_build_object('liste', v_tout);
end $$;


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
  elsif p_source = 'mur'      then
    update asso_mur_radios      set statut = v_statut where id = p_id;
  elsif p_source = 'sujet'    then
    update asso_sujets          set statut = v_statut where id = p_id;
  elsif p_source = 'radio'    then
    update asso_radios_proposees set statut = v_statut where id = p_id;
  elsif p_source = 'analyse'  then
    update asso_analyses        set statut = v_statut where id = p_id;
  else
    return jsonb_build_object('erreur', 'source inconnue');
  end if;

  get diagnostics v_n = row_count;
  return jsonb_build_object('statut', v_statut, 'lignes', v_n);
end $$;


-- ---------------------------------------------------------------------
--  La liste des inscrits aux nouvelles, pour votre page Moderation.
-- ---------------------------------------------------------------------
create or replace function asso_abonnes_liste()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  return jsonb_build_object(
    'nombre', (select count(*) from asso_abonnes where not desinscrit),
    'liste', coalesce((
      select jsonb_agg(x order by x->>'cree_le' desc)
        from (select jsonb_build_object('email', a.email, 'langue', a.langue,
                                        'cree_le', a.cree_le) as x
                from asso_abonnes a
               where not a.desinscrit
               order by a.cree_le desc
               limit 500) t), '[]'::jsonb));
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_moderation() to authenticated';
    execute 'grant execute on function asso_moderer(text, bigint, text) to authenticated';
    execute 'grant execute on function asso_abonnes_liste() to authenticated';
  end if;
end $$;
