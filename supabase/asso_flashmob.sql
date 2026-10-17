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
--     Trois choix par personne, pas un de plus.
-- ============================================================

create table if not exists public.asso_votes (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references auth.users(id) on delete cascade,
  chanson  text not null,
  cree_le  timestamptz not null default now(),
  unique (user_id, chanson)
);

create index if not exists asso_votes_chanson_idx on public.asso_votes (chanson);

-- la limite de trois choix, tenue par la base elle meme
create or replace function public.asso_votes_trois_max()
returns trigger language plpgsql as $$
begin
  if (select count(*) from public.asso_votes where user_id = new.user_id) >= 3 then
    raise exception 'Trois chansons au maximum.';
  end if;
  return new;
end $$;

drop trigger if exists asso_votes_trois_max_trg on public.asso_votes;
create trigger asso_votes_trois_max_trg
  before insert on public.asso_votes
  for each row execute function public.asso_votes_trois_max();

alter table public.asso_votes enable row level security;

drop policy if exists "un fan lit ses votes" on public.asso_votes;
create policy "un fan lit ses votes"
  on public.asso_votes for select
  using (auth.uid() = user_id);

drop policy if exists "un fan vote" on public.asso_votes;
create policy "un fan vote"
  on public.asso_votes for insert
  with check (auth.uid() = user_id);

drop policy if exists "un fan retire son vote" on public.asso_votes;
create policy "un fan retire son vote"
  on public.asso_votes for delete
  using (auth.uid() = user_id);

drop policy if exists "la moderatrice voit les votes" on public.asso_votes;
create policy "la moderatrice voit les votes"
  on public.asso_votes for all
  using ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr')
  with check ((auth.jwt() ->> 'email') = 'elisabeth.sikora@orange.fr');

-- les totaux, visibles de tous, sans jamais dire qui a vote quoi
create or replace view public.asso_votes_totaux as
  select chanson, count(*)::int as total
  from public.asso_votes
  group by chanson;

grant select on public.asso_votes_totaux to anon, authenticated;


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
--  select * from public.asso_votes_totaux order by total desc;
-- ============================================================
