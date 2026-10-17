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
