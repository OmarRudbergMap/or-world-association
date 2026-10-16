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
