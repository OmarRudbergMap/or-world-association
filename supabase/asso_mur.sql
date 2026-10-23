-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LE MUR DES RADIOS
--
--  Les fans racontent ce qui s'est passe avec une radio : une reponse,
--  un passage a l'antenne, un accueil sympathique. Rien ne parait sans
--  votre accord : chaque message passe par la moderation.
--
--  Ce script ne supprime rien et peut etre passe plusieurs fois.
-- =====================================================================

create table if not exists asso_mur_radios (
  id        bigserial primary key,
  membre    uuid,
  pseudo    text not null,
  radio     text not null,
  pays      text,
  message   text not null,
  langue    text,
  statut    text not null default 'en attente',
  cree_le   timestamptz not null default now()
);

alter table asso_mur_radios enable row level security;

-- tout le monde peut lire ce qui est publie
do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'asso_mur_radios'
                    and policyname = 'lire le mur publie') then
    execute 'create policy "lire le mur publie" on asso_mur_radios
               for select to anon, authenticated
               using (statut = ''publie'')';
  end if;
end $$;

-- tout le monde peut deposer un message, membre ou non
do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'asso_mur_radios'
                    and policyname = 'deposer sur le mur') then
    execute 'create policy "deposer sur le mur" on asso_mur_radios
               for insert to anon, authenticated
               with check (statut = ''en attente'')';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant select, insert on asso_mur_radios to anon';
    execute 'grant usage, select on sequence asso_mur_radios_id_seq to anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant select, insert on asso_mur_radios to authenticated';
    execute 'grant usage, select on sequence asso_mur_radios_id_seq to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  Le mur rejoint la file de moderation, en sixieme position.
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

  -- le mur des radios
  select v_tout || coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_tout
  from (select jsonb_build_object('source','mur','id',m.id,'date',m.cree_le,
      'titre', coalesce(nullif(m.pseudo,''), '—'),
      'detail', concat_ws(' · ', nullif(m.radio,''), nullif(m.pays,'')),
      'extrait', left(coalesce(m.message,''), 600), 'lien', null) as x
    from asso_mur_radios m where m.statut in ('en attente','en_attente')) t;

  return jsonb_build_object('liste', v_tout);
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_moderation() to authenticated';
  end if;
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
