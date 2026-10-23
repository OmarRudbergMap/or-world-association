-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LE COMPTEUR DE VISITES
--
--  Une ligne par page vue. Pas de cookie, pas d'adresse IP, pas
--  d'identifiant : rien ici ne permet de reconnaitre une personne,
--  ni de savoir qu'elle est deja venue hier. Le pays est deduit du
--  fuseau horaire du navigateur, cote visiteur, avant l'envoi.
--
--  Seul le bureau peut lire ces chiffres, et uniquement en bloc, par
--  l'intermediaire de asso_visites_tableau().
--
--  Ce script ne supprime rien et peut etre passe plusieurs fois.
-- =====================================================================

create table if not exists asso_visites (
  id      bigserial primary key,
  jour    date not null default (now() at time zone 'Europe/Paris')::date,
  page    text,
  pays    text,
  langue  text,
  session boolean not null default false,
  cree_le timestamptz not null default now()
);

create index if not exists asso_visites_jour on asso_visites (jour);
create index if not exists asso_visites_pays on asso_visites (pays);

alter table asso_visites enable row level security;

-- Deposer une visite : tout le monde. Relire : personne, sauf par la
-- fonction du tableau de bord, plus bas.
do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'asso_visites'
                    and policyname = 'compter une visite') then
    execute 'create policy "compter une visite" on asso_visites
               for insert to anon, authenticated
               with check (true)';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant insert (page, pays, langue, session) on asso_visites to anon';
    execute 'grant usage, select on sequence asso_visites_id_seq to anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant insert (page, pays, langue, session) on asso_visites to authenticated';
    execute 'grant usage, select on sequence asso_visites_id_seq to authenticated';
  end if;
end $$;
-- Remarque : la permission ne porte que sur quatre colonnes. Le jour
-- et l'heure sont poses par la base, personne ne peut les inventer.


-- ---------------------------------------------------------------------
--  Un peu de tenue : on refuse les valeurs manifestement fausses.
-- ---------------------------------------------------------------------
create or replace function asso_visites_propre()
returns trigger
language plpgsql
as $$
begin
  new.page   := nullif(left(coalesce(new.page, ''), 60), '');
  new.langue := nullif(left(coalesce(new.langue, ''), 5), '');
  if new.pays is not null and new.pays !~ '^[A-Za-z]{2}$' then
    new.pays := null;
  else
    new.pays := upper(new.pays);
  end if;
  return new;
end $$;

drop trigger if exists asso_visites_propre_trig on asso_visites;
create trigger asso_visites_propre_trig
  before insert on asso_visites
  for each row execute function asso_visites_propre();


-- ---------------------------------------------------------------------
--  L'historique repris de l'ancien site, mois par mois et pays par
--  pays. Ces chiffres ne sont pas comptes ici : ils viennent des
--  exports de l'ancien hebergeur, et ne bougeront plus.
-- ---------------------------------------------------------------------
create table if not exists asso_visites_histoire (
  mois       text not null,
  pays       text,
  vues       int not null default 0,
  sessions   int not null default 0,
  visiteurs  int not null default 0,
  source     text not null default 'wix'
);

-- « -- » represente les visites dont le pays n'a pas ete capture.
create unique index if not exists asso_visites_histoire_cle
  on asso_visites_histoire (mois, coalesce(pays, '--'));

alter table asso_visites_histoire enable row level security;


-- ---------------------------------------------------------------------
--  Le tableau de bord. Reserve au bureau.
-- ---------------------------------------------------------------------
create or replace function asso_visites_tableau(p_mois text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mois    jsonb;
  v_pays    jsonb;
  v_pages   jsonb;
  v_jours   jsonb;
  v_courant text := to_char((now() at time zone 'Europe/Paris'), 'YYYY-MM');
  v_vise    text := coalesce(p_mois, v_courant);
  v_ancien  boolean;
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  if p_mois is not null and p_mois !~ '^[0-9]{4}-[0-9]{2}$' then
    return jsonb_build_object('erreur', 'mois mal ecrit');
  end if;

  -- ce mois vient-il des releves de l'ancien site ?
  v_ancien := exists (select 1 from asso_visites_histoire h where h.mois = v_vise);

  -- la suite des mois : l'historique d'abord, les visites comptees ensuite
  select coalesce(jsonb_agg(x order by x->>'mois'), '[]'::jsonb) into v_mois
  from (
    select jsonb_build_object('mois', h.mois,
                              'vues', sum(h.vues),
                              'sessions', sum(h.sessions),
                              'source', 'ancien site') as x
      from asso_visites_histoire h
     group by h.mois
    union all
    select jsonb_build_object('mois', to_char(v.jour, 'YYYY-MM'),
                              'vues', count(*),
                              'sessions', count(*) filter (where v.session),
                              'source', 'site') as x
      from asso_visites v
     group by to_char(v.jour, 'YYYY-MM')
  ) t;

  -- les pays du mois vise
  if v_ancien then
    select coalesce(jsonb_agg(x order by (x->>'vues')::int desc), '[]'::jsonb) into v_pays
    from (select jsonb_build_object('pays', h.pays, 'vues', h.vues) as x
            from asso_visites_histoire h
           where h.mois = v_vise and h.pays is not null) t;
  else
    select coalesce(jsonb_agg(x order by (x->>'vues')::int desc), '[]'::jsonb) into v_pays
    from (select jsonb_build_object('pays', v.pays, 'vues', count(*)) as x
            from asso_visites v
           where to_char(v.jour, 'YYYY-MM') = v_vise and v.pays is not null
           group by v.pays) t;
  end if;

  -- les pages du mois vise : l'ancien site ne les a pas laissees
  select coalesce(jsonb_agg(x order by (x->>'vues')::int desc), '[]'::jsonb) into v_pages
  from (select jsonb_build_object('page', v.page, 'vues', count(*)) as x
          from asso_visites v
         where to_char(v.jour, 'YYYY-MM') = v_vise and v.page is not null
         group by v.page
         limit 12) t;

  -- le detail jour par jour, quand il existe
  select coalesce(jsonb_agg(x order by x->>'jour'), '[]'::jsonb) into v_jours
  from (select jsonb_build_object('jour', to_char(v.jour, 'YYYY-MM-DD'),
                                  'vues', count(*),
                                  'sessions', count(*) filter (where v.session)) as x
          from asso_visites v
         where to_char(v.jour, 'YYYY-MM') = v_vise
         group by v.jour) t;

  return jsonb_build_object(
    'mois',        v_mois,
    'mois_vise',   v_vise,
    'choisi',      p_mois is not null,
    'ancien',      v_ancien,
    'pays',        v_pays,
    'pages',       v_pages,
    'jours',       v_jours,
    'resume', jsonb_build_object(
       'vues', case when v_ancien
                    then (select coalesce(sum(h.vues), 0) from asso_visites_histoire h where h.mois = v_vise)
                    else (select count(*) from asso_visites v where to_char(v.jour, 'YYYY-MM') = v_vise) end,
       'sessions', case when v_ancien
                    then (select coalesce(sum(h.sessions), 0) from asso_visites_histoire h where h.mois = v_vise)
                    else (select count(*) from asso_visites v where to_char(v.jour, 'YYYY-MM') = v_vise and v.session) end,
       'pays', case when v_ancien
                    then (select count(*) from asso_visites_histoire h where h.mois = v_vise and h.pays is not null)
                    else (select count(distinct v.pays) from asso_visites v where to_char(v.jour, 'YYYY-MM') = v_vise and v.pays is not null) end),
    'tous_pays', (select coalesce(jsonb_agg(x order by (x->>'vues')::int desc), '[]'::jsonb)
                    from (select jsonb_build_object('pays', p.pays, 'vues', sum(p.vues)) as x
                            from (select h.pays, h.vues from asso_visites_histoire h where h.pays is not null
                                  union all
                                  select v.pays, 1 from asso_visites v where v.pays is not null) p
                           group by p.pays) q),
    'depuis_le', (select min(jour) from asso_visites));
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_visites_tableau(text) to authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------
--  L'historique de l'ancien site, janvier a mai 2026.
--  Releve sur les exports de l'ancien hebergeur. Pour janvier, fevrier,
--  mars et avril, la somme des pays correspond exactement au total
--  annonce par l'hebergeur : les chiffres sont surs.
--  Pour mai, le bas du tableau avait ete coupe a la capture : 7 vues et
--  4 sessions sont rangees sans pays, pour que le total du mois reste
--  juste. Elles n'apparaissent donc pas dans la liste des pays.
-- ---------------------------------------------------------------------
insert into asso_visites_histoire (mois, pays, vues, sessions, visiteurs) values
('2026-01','FR',189,65,31),
('2026-01','DE',60,19,15),
('2026-01','CA',47,18,10),
('2026-01','US',40,17,12),
('2026-01','GB',35,15,13),
('2026-01','PL',23,12,7),
('2026-01','BE',18,10,7),
('2026-01','ES',8,7,5),
('2026-01','NL',21,6,5),
('2026-01','CZ',7,6,4),
('2026-01','HU',11,5,4),
('2026-01','AT',17,5,4),
('2026-01','SE',5,4,4),
('2026-01','FI',4,4,4),
('2026-01','MY',5,4,2),
('2026-01','AR',7,4,3),
('2026-01','AU',7,4,4),
('2026-01','NO',6,3,2),
('2026-01','LV',4,3,2),
('2026-01','CH',3,2,1),
('2026-01','LK',2,1,1),
('2026-01','RU',1,1,1),
('2026-01','BG',1,1,1),
('2026-01','IN',1,1,1),
('2026-01','EE',1,1,1),
('2026-01','PT',1,1,1),
('2026-01','IS',4,1,1),
('2026-01','SK',1,1,1),
('2026-01','NZ',1,1,1),
('2026-01','RO',4,1,1),
('2026-01','DK',1,1,1),
('2026-02','FR',346,124,47),
('2026-02','DE',143,66,32),
('2026-02','US',99,55,21),
('2026-02','PL',83,34,19),
('2026-02','CA',66,26,12),
('2026-02','GB',47,20,17),
('2026-02','CZ',25,20,5),
('2026-02','NL',61,15,9),
('2026-02','HU',23,12,5),
('2026-02','SE',28,12,7),
('2026-02','BE',22,12,9),
('2026-02','ES',15,11,9),
('2026-02','NO',14,7,4),
('2026-02','AT',18,6,4),
('2026-02','FI',16,5,4),
('2026-02','LV',7,5,4),
('2026-02','AU',7,4,4),
('2026-02','CH',10,4,3),
('2026-02','PT',8,4,3),
('2026-02','IT',22,4,3),
('2026-02','AR',7,4,3),
('2026-02','MY',5,4,2),
('2026-02','RO',19,3,3),
('2026-02','NZ',2,2,2),
('2026-02','DK',2,2,2),
('2026-02','IN',4,2,1),
('2026-02','EE',5,2,1),
('2026-02','IE',1,1,1),
('2026-02','LT',1,1,1),
('2026-02','LK',2,1,1),
('2026-02','MT',1,1,1),
('2026-02','BG',1,1,1),
('2026-02','SK',1,1,1),
('2026-02','IS',4,1,1),
('2026-02','GE',1,1,1),
('2026-02','RU',1,1,1),
('2026-02','SG',1,1,1),
('2026-03','FR',484,200,59),
('2026-03','DE',175,81,37),
('2026-03','US',110,65,25),
('2026-03','PL',94,38,21),
('2026-03','CA',80,30,14),
('2026-03','ES',31,25,12),
('2026-03','CZ',35,24,5),
('2026-03','GB',52,22,19),
('2026-03','HU',35,20,6),
('2026-03','BE',37,17,10),
('2026-03','NL',62,16,9),
('2026-03','SE',38,15,9),
('2026-03','NO',16,8,5),
('2026-03','PK',13,8,2),
('2026-03','AT',18,6,4),
('2026-03','LV',7,5,4),
('2026-03','IT',24,5,4),
('2026-03','CH',11,5,4),
('2026-03','FI',16,5,4),
('2026-03','AR',7,4,3),
('2026-03','MY',5,4,2),
('2026-03','PT',8,4,3),
('2026-03','RO',20,4,4),
('2026-03','DK',9,4,3),
('2026-03','AU',7,4,4),
('2026-03','EE',5,2,1),
('2026-03','IN',4,2,1),
('2026-03','NZ',2,2,2),
('2026-03','LK',2,1,1),
('2026-03','BG',1,1,1),
('2026-03','LT',1,1,1),
('2026-03','SK',1,1,1),
('2026-03','RU',1,1,1),
('2026-03','IS',4,1,1),
('2026-03','SG',1,1,1),
('2026-03','MT',1,1,1),
('2026-03','GE',1,1,1),
('2026-03','IE',1,1,1),
('2026-04','FR',629,270,68),
('2026-04','DE',219,103,55),
('2026-04','US',123,72,29),
('2026-04','PL',124,52,23),
('2026-04','CA',92,35,17),
('2026-04','ES',46,33,17),
('2026-04','CZ',48,31,5),
('2026-04','BE',60,24,12),
('2026-04','GB',56,23,20),
('2026-04','HU',37,22,6),
('2026-04','SE',44,21,15),
('2026-04','NL',66,18,11),
('2026-04','FI',26,11,5),
('2026-04','NO',26,11,6),
('2026-04','PK',13,8,2),
('2026-04','CH',15,8,6),
('2026-04','AT',18,6,4),
('2026-04','LV',7,5,4),
('2026-04','IT',24,5,4),
('2026-04','PT',8,4,3),
('2026-04','AU',7,4,4),
('2026-04','MY',5,4,2),
('2026-04','DK',9,4,3),
('2026-04','RO',20,4,4),
('2026-04','AR',7,4,3),
('2026-04','IN',5,3,2),
('2026-04','NZ',2,2,2),
('2026-04','EE',5,2,1),
('2026-04','IE',1,1,1),
('2026-04','MT',1,1,1),
('2026-04','SG',1,1,1),
('2026-04','BR',3,1,1),
('2026-04','SK',1,1,1),
('2026-04','RU',1,1,1),
('2026-04','LK',2,1,1),
('2026-04','IS',4,1,1),
('2026-04','LT',1,1,1),
('2026-04','GE',1,1,1),
('2026-04','BG',1,1,1),
('2026-05','FR',666,292,72),
('2026-05','DE',222,106,57),
('2026-05','US',124,73,30),
('2026-05','PL',124,52,23),
('2026-05','CA',109,39,19),
('2026-05','ES',48,35,17),
('2026-05','CZ',48,31,5),
('2026-05','BE',68,27,13),
('2026-05','HU',38,23,6),
('2026-05','SE',46,23,16),
('2026-05','GB',56,23,20),
('2026-05','NL',69,20,11),
('2026-05','NO',27,12,7),
('2026-05','FI',26,11,5),
('2026-05','CH',15,8,6),
('2026-05','PK',13,8,2),
('2026-05','AT',18,6,4),
('2026-05','IT',25,6,5),
('2026-05','LV',7,5,4),
('2026-05','PT',8,4,3),
('2026-05','DK',9,4,3),
('2026-05','AU',7,4,4),
('2026-05','MY',5,4,2),
('2026-05','RO',20,4,4),
('2026-05','IN',5,3,2),
('2026-05','NZ',2,2,2),
('2026-05','EE',5,2,1),
('2026-05','BG',4,2,2),
('2026-05','JP',5,2,2),
('2026-05','RU',2,2,2),
('2026-05','SG',1,1,1),
('2026-05','SK',1,1,1),
('2026-05','IS',4,1,1),
('2026-05','IE',1,1,1),
('2026-05','BR',3,1,1),
('2026-05','LK',2,1,1),
('2026-05','LT',1,1,1),
('2026-05','GE',1,1,1),
('2026-05','MT',1,1,1),
('2026-05',null,7,4,0)
on conflict (mois, coalesce(pays, '--')) do update
   set vues = excluded.vues, sessions = excluded.sessions, visiteurs = excluded.visiteurs;


-- =====================================================================
--  VOS ADHERENTS, EN TROIS CHIFFRES
--
--  On reprend exactement la regle deja utilisee par les compteurs
--  publics du site : est adherent a jour celui dont l'adhesion n'est
--  pas encore arrivee a son terme, les essais mis de cote. Ainsi le
--  chiffre de votre moderation et celui affiche sur le site ne peuvent
--  pas se contredire.
--
--  Rien ici ne relie une visite a une personne : ce sont deux comptes
--  separes, qui ne se croisent jamais.
-- =====================================================================
create or replace function asso_adherents_compte()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_debut date := date_trunc('month', current_date)::date;
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  return jsonb_build_object(
    'a_jour', (select count(*) from asso_adhesions a
                where a.date_fin >= current_date
                  and coalesce(a.statut, 'actif') <> 'essai'),

    'avec_compte', (select count(*) from asso_adhesions a
                     where a.date_fin >= current_date
                       and coalesce(a.statut, 'actif') <> 'essai'
                       and a.membre is not null),

    'nouveaux', (select count(*) from asso_adhesions a
                  where a.date_debut >= v_debut
                    and coalesce(a.statut, 'actif') <> 'essai'),

    'a_renouveler', (select count(*) from asso_adhesions a
                      where a.date_fin >= current_date
                        and a.date_fin <= current_date + 30
                        and coalesce(a.statut, 'actif') <> 'essai'),

    'pays', (select count(distinct a.pays) from asso_adhesions a
              where a.date_fin >= current_date
                and coalesce(a.statut, 'actif') <> 'essai'
                and a.pays is not null and a.pays <> ''),

    'depuis_toujours', (select count(distinct lower(a.email)) from asso_adhesions a
                         where a.email is not null and a.email <> ''),

    -- le pays tel que l'adherent l'a ecrit : la page de moderation se
    -- charge de le reconnaitre pour le poser sur la carte
    'pays_liste', (select coalesce(jsonb_agg(x order by (x->>'n')::int desc), '[]'::jsonb)
                     from (select jsonb_build_object('nom', a.pays, 'n', count(*)) as x
                             from asso_adhesions a
                            where a.date_fin >= current_date
                              and coalesce(a.statut, 'actif') <> 'essai'
                              and a.pays is not null and a.pays <> ''
                            group by a.pays) t)
  );
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_adherents_compte() to authenticated';
  end if;
end $$;


-- =====================================================================
--  ILS ONT PAYE, IL LEUR MANQUE LE COMPTE
--
--  Ces personnes figurent dans vos adhesions, mais aucun compte du
--  site ne porte leur adresse. Elles ne peuvent donc pas voir leur
--  carte. La liste sert a les relancer, une par une.
--
--  La fonction ne depend d'aucun autre script : elle interroge
--  directement les adhesions et les comptes.
-- =====================================================================
create or replace function asso_a_inscrire_liste()
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
    'liste', coalesce((
      select jsonb_agg(x order by (x->>'numero')::int nulls last)
        from (select jsonb_build_object(
                'numero',  a.numero_membre,
                'prenom',  a.prenom,
                'nom',     a.nom,
                'email',   a.email,
                'pays',    a.pays,
                'langue',  a.langue,
                'depuis',  a.date_debut,
                'a_jour',  (a.date_fin >= current_date)) as x
                from asso_adhesions a
               where a.membre is null
                 and a.email is not null and a.email <> ''
                 and coalesce(a.statut, 'actif') <> 'essai'
                 and not exists (select 1 from auth.users u
                                  where lower(u.email) = lower(a.email))
               order by a.numero_membre
               limit 300) t), '[]'::jsonb));
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_a_inscrire_liste() to authenticated';
  end if;
end $$;
