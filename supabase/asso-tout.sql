-- ============================================================
--  O.R. WORLD ASSOCIATION, flashmob mondial #DanceWithOmar
--  TOUT EN UN : ambassadeurs, vote, mur des videos, rendez-vous
--
--  A lancer dans le Supabase de l'ASSOCIATION
--  (identifiant gkineosvtpswcbflqvyu), jamais dans l'autre.
--
--  SQL Editor, New query, coller tout, Run.
--  On peut le relancer sans rien casser.
--
--  Le vote des chansons s'appelle asso_votes_chansons, pour ne pas
--  toucher a asso_votes qui sert aux votes des projets.
-- ============================================================

-- ============================================================
--  FLASHMOB MONDIAL #DanceWithOmar
--  Table des ambassadeurs : candidatures et annuaire public
--
--  ⚠️  À lancer dans le Supabase de l'ASSOCIATION,
--      surtout pas dans celui de l'autre site.
--
--  Supabase, SQL Editor, New query, coller, Run.
-- ============================================================

create table if not exists public.asso_ambassadeurs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete cascade,

  -- visible publiquement une fois la candidature validée
  pseudo      text not null,
  pays        text not null,
  langues     text,
  instagram   text,
  tiktok      text,
  youtube     text,
  x_twitter   text,

  -- privé : seule la modératrice le voit
  ville       text,
  message     text,

  statut      text not null default 'en_attente'
              check (statut in ('en_attente','valide','refuse')),
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now(),

  -- au moins un compte de réseau social
  constraint au_moins_un_reseau check (
    coalesce(instagram,'') <> '' or coalesce(tiktok,'') <> ''
    or coalesce(youtube,'') <> '' or coalesce(x_twitter,'') <> ''
  )
);

create index if not exists asso_ambassadeurs_statut_idx on public.asso_ambassadeurs (statut);
create index if not exists asso_ambassadeurs_pays_idx   on public.asso_ambassadeurs (pays);

-- la date de mise à jour se tient à jour toute seule
create or replace function public.asso_ambassadeurs_maj_le()
returns trigger language plpgsql as $$
begin
  new.maj_le = now();
  return new;
end $$;

drop trigger if exists asso_ambassadeurs_maj_le_trg on public.asso_ambassadeurs;
create trigger asso_ambassadeurs_maj_le_trg
  before update on public.asso_ambassadeurs
  for each row execute function public.asso_ambassadeurs_maj_le();

-- ============================================================
--  Qui a le droit de voir quoi
-- ============================================================
alter table public.asso_ambassadeurs enable row level security;

-- 1. tout le monde voit les ambassadeurs validés
drop policy if exists "lecture publique des ambassadeurs valides" on public.asso_ambassadeurs;
create policy "lecture publique des ambassadeurs valides"
  on public.asso_ambassadeurs for select
  using (statut = 'valide');

-- 2. un fan connecté voit sa propre candidature, même en attente
drop policy if exists "un fan lit sa candidature" on public.asso_ambassadeurs;
create policy "un fan lit sa candidature"
  on public.asso_ambassadeurs for select
  using (auth.uid() = user_id);

-- 3. un fan connecté dépose sa candidature, une seule
drop policy if exists "un fan depose sa candidature" on public.asso_ambassadeurs;
create policy "un fan depose sa candidature"
  on public.asso_ambassadeurs for insert
  with check (auth.uid() = user_id and statut = 'en_attente');

-- 4. un fan corrige sa candidature tant qu'elle n'est pas traitée
drop policy if exists "un fan corrige sa candidature" on public.asso_ambassadeurs;
create policy "un fan corrige sa candidature"
  on public.asso_ambassadeurs for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and statut = 'en_attente');

-- 5. la modératrice fait tout
drop policy if exists "la moderatrice fait tout" on public.asso_ambassadeurs;
create policy "la moderatrice fait tout"
  on public.asso_ambassadeurs for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');

-- ============================================================
--  Vue publique : seulement les colonnes visibles de tous.
--  L'annuaire du site lit cette vue, jamais la table entière,
--  comme ça la ville et la motivation ne sortent jamais.
-- ============================================================
create or replace view public.asso_ambassadeurs_publics as
  select pseudo, pays, langues, instagram, tiktok, youtube, x_twitter, cree_le
  from public.asso_ambassadeurs
  where statut = 'valide';

grant select on public.asso_ambassadeurs_publics to anon, authenticated;

-- ============================================================
--  Pour valider une candidature à la main si besoin :
--  update public.asso_ambassadeurs set statut = 'valide' where pseudo = '...';
-- ============================================================


-- ============================================================
--  FLASHMOB MONDIAL #DanceWithOmar
--  Le vote des chansons et le mur des videos
--
--  A lancer dans le Supabase de l'ASSOCIATION
--  (projet gkineosvtpswcbflqvyu), surtout pas dans l'autre.
--
--  Supabase, SQL Editor, New query, coller, Run.
-- ============================================================


-- ============================================================
--  1. LE VOTE DES CHANSONS
--     Trois choix par personne. Table separee de asso_votes,
--     qui sert deja aux votes des projets de l'association., pas un de plus.
-- ============================================================

create table if not exists public.asso_votes_chansons (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references auth.users(id) on delete cascade,
  chanson  text not null,
  cree_le  timestamptz not null default now(),
  unique (user_id, chanson)
);

create index if not exists asso_votes_chansons_idx on public.asso_votes_chansons (chanson);

-- la limite de trois choix, tenue par la base elle meme
create or replace function public.asso_votes_chansons_trois_max()
returns trigger language plpgsql as $$
begin
  if (select count(*) from public.asso_votes_chansons where user_id = new.user_id) >= 3 then
    raise exception 'Trois chansons au maximum.';
  end if;
  return new;
end $$;

drop trigger if exists asso_votes_chansons_trois_max_trg on public.asso_votes_chansons;
create trigger asso_votes_chansons_trois_max_trg
  before insert on public.asso_votes_chansons
  for each row execute function public.asso_votes_chansons_trois_max();

alter table public.asso_votes_chansons enable row level security;

drop policy if exists "un fan lit ses votes" on public.asso_votes_chansons;
create policy "un fan lit ses votes"
  on public.asso_votes_chansons for select
  using (auth.uid() = user_id);

drop policy if exists "un fan vote" on public.asso_votes_chansons;
create policy "un fan vote"
  on public.asso_votes_chansons for insert
  with check (auth.uid() = user_id);

drop policy if exists "un fan retire son vote" on public.asso_votes_chansons;
create policy "un fan retire son vote"
  on public.asso_votes_chansons for delete
  using (auth.uid() = user_id);

drop policy if exists "la moderatrice voit les votes" on public.asso_votes_chansons;
create policy "la moderatrice voit les votes"
  on public.asso_votes_chansons for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');

-- les totaux, visibles de tous, sans jamais dire qui a vote quoi
create or replace view public.asso_votes_chansons_totaux as
  select chanson, count(*)::int as total
  from public.asso_votes_chansons
  group by chanson;

grant select on public.asso_votes_chansons_totaux to anon, authenticated;


-- ============================================================
--  2. LE MUR DES VIDEOS
--     Chapitre 1 a 4, et 5 pour la choregraphie complete.
--     Rien n'apparait avant d'avoir ete verifie.
-- ============================================================

create table if not exists public.asso_videos (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  pseudo    text not null,
  pays      text,
  chapitre  int  not null default 1 check (chapitre between 1 and 5),
  reseau    text not null check (reseau in ('instagram','tiktok','youtube','autre')),
  lien      text not null,
  statut    text not null default 'en_attente'
            check (statut in ('en_attente','valide','refuse')),
  cree_le   timestamptz not null default now(),
  constraint lien_http check (lien like 'http%')
);

create index if not exists asso_videos_chap_idx   on public.asso_videos (chapitre, statut);
create index if not exists asso_videos_statut_idx on public.asso_videos (statut);

alter table public.asso_videos enable row level security;

drop policy if exists "tout le monde voit les videos validees" on public.asso_videos;
create policy "tout le monde voit les videos validees"
  on public.asso_videos for select
  using (statut = 'valide');

drop policy if exists "un fan lit ses videos" on public.asso_videos;
create policy "un fan lit ses videos"
  on public.asso_videos for select
  using (auth.uid() = user_id);

drop policy if exists "un fan depose une video" on public.asso_videos;
create policy "un fan depose une video"
  on public.asso_videos for insert
  with check (auth.uid() = user_id and statut = 'en_attente');

drop policy if exists "un fan retire sa video" on public.asso_videos;
create policy "un fan retire sa video"
  on public.asso_videos for delete
  using (auth.uid() = user_id);

drop policy if exists "la moderatrice fait tout sur les videos" on public.asso_videos;
create policy "la moderatrice fait tout sur les videos"
  on public.asso_videos for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');

create or replace view public.asso_videos_publiques as
  select id, pseudo, pays, chapitre, reseau, lien, cree_le
  from public.asso_videos
  where statut = 'valide'
  order by cree_le desc;

grant select on public.asso_videos_publiques to anon, authenticated;


-- ============================================================
--  Pour la moderation, a la main quand il le faut :
--
--  select pseudo, chapitre, reseau, lien, cree_le
--    from public.asso_videos where statut = 'en_attente'
--    order by cree_le;
--
--  update public.asso_videos set statut = 'valide' where id = '...';
--  update public.asso_videos set statut = 'refuse' where id = '...';
--
--  Pour suivre le vote :
--  select * from public.asso_votes_chansons_totaux order by total desc;
-- ============================================================


-- ============================================================
--  FLASHMOB MONDIAL #DanceWithOmar
--  Les rendez-vous dans les rues du monde
--
--  Proposes par les ambassadeurs valides, verifies par
--  l'association, ouverts a tous les fans.
--
--  A lancer dans le Supabase de l'ASSOCIATION
--  (projet gkineosvtpswcbflqvyu), surtout pas dans l'autre.
--  A lancer APRES asso_ambassadeurs.sql.
-- ============================================================

create table if not exists public.asso_rdv (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references auth.users(id) on delete cascade,
  pseudo   text not null,
  pays     text not null,
  ville    text not null,
  lieu     text not null,
  jour     date not null,
  heure    text not null,
  mot      text,
  contact  text,
  statut   text not null default 'en_attente'
           check (statut in ('en_attente','valide','refuse')),
  cree_le  timestamptz not null default now()
);

create index if not exists asso_rdv_jour_idx on public.asso_rdv (jour);
create index if not exists asso_rdv_statut_idx on public.asso_rdv (statut);

alter table public.asso_rdv enable row level security;

-- qui est ambassadeur valide
create or replace function public.est_ambassadeur()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.asso_ambassadeurs
    where user_id = auth.uid() and statut = 'valide'
  );
$$;

grant execute on function public.est_ambassadeur() to anon, authenticated;

drop policy if exists "tout le monde voit les rdv valides" on public.asso_rdv;
create policy "tout le monde voit les rdv valides"
  on public.asso_rdv for select
  using (statut = 'valide');

drop policy if exists "un ambassadeur lit ses rdv" on public.asso_rdv;
create policy "un ambassadeur lit ses rdv"
  on public.asso_rdv for select
  using (auth.uid() = user_id);

-- seuls les ambassadeurs valides proposent un rendez-vous
drop policy if exists "un ambassadeur propose un rdv" on public.asso_rdv;
create policy "un ambassadeur propose un rdv"
  on public.asso_rdv for insert
  with check (auth.uid() = user_id and statut = 'en_attente' and public.est_ambassadeur());

drop policy if exists "un ambassadeur retire son rdv" on public.asso_rdv;
create policy "un ambassadeur retire son rdv"
  on public.asso_rdv for delete
  using (auth.uid() = user_id);

drop policy if exists "la moderatrice fait tout sur les rdv" on public.asso_rdv;
create policy "la moderatrice fait tout sur les rdv"
  on public.asso_rdv for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');


-- ============================================================
--  "Je viens" : un fan connecte s'annonce, une fois par rdv
-- ============================================================

create table if not exists public.asso_rdv_oui (
  rdv_id   uuid not null references public.asso_rdv(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  cree_le  timestamptz not null default now(),
  primary key (rdv_id, user_id)
);

alter table public.asso_rdv_oui enable row level security;

drop policy if exists "un fan lit ses presences" on public.asso_rdv_oui;
create policy "un fan lit ses presences"
  on public.asso_rdv_oui for select
  using (auth.uid() = user_id);

drop policy if exists "un fan dit qu'il vient" on public.asso_rdv_oui;
create policy "un fan dit qu'il vient"
  on public.asso_rdv_oui for insert
  with check (auth.uid() = user_id);

drop policy if exists "un fan se desiste" on public.asso_rdv_oui;
create policy "un fan se desiste"
  on public.asso_rdv_oui for delete
  using (auth.uid() = user_id);

drop policy if exists "la moderatrice voit les presences" on public.asso_rdv_oui;
create policy "la moderatrice voit les presences"
  on public.asso_rdv_oui for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');


-- ============================================================
--  La vue publique : les rendez-vous a venir, avec le nombre
--  de personnes annoncees. Jamais qui vient, juste combien.
-- ============================================================
create or replace view public.asso_rdv_publics as
  select r.id, r.pseudo, r.pays, r.ville, r.lieu, r.jour, r.heure,
         r.mot, r.contact, r.cree_le,
         (select count(*) from public.asso_rdv_oui o where o.rdv_id = r.id)::int as viennent
  from public.asso_rdv r
  where r.statut = 'valide' and r.jour >= current_date - 1
  order by r.jour, r.heure;

grant select on public.asso_rdv_publics to anon, authenticated;


-- ============================================================
--  Moderation :
--
--  select pseudo, pays, ville, lieu, jour, heure, mot, contact
--    from public.asso_rdv where statut = 'en_attente' order by cree_le;
--
--  update public.asso_rdv set statut = 'valide' where id = '...';
--  update public.asso_rdv set statut = 'refuse' where id = '...';
-- ============================================================
