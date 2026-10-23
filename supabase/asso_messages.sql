-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LE FORMULAIRE DE CONTACT
--
--  Jusqu'ici le bouton « Envoyer » n'etait relie a rien : les messages
--  des fans se perdaient. Desormais chaque message est conserve ici,
--  apparait dans votre page Moderation, et vous est annonce par
--  courriel sur orworldassociation@gmail.com.
--
--  Ce script ne supprime rien et peut etre passe plusieurs fois.
-- =====================================================================

create table if not exists asso_messages (
  id        bigserial primary key,
  nom       text not null,
  email     text not null,
  sujet     text,
  sujet_cle text,
  message   text not null,
  langue    text,
  membre    uuid,
  traite    boolean not null default false,
  traite_le timestamptz,
  cree_le   timestamptz not null default now()
);

create index if not exists asso_messages_attente
  on asso_messages (cree_le desc) where traite = false;

alter table asso_messages enable row level security;

-- On peut deposer un message, membre ou non. Personne ne peut relire
-- ce qui a ete depose : seule la moderation y a acces, plus bas.
do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'asso_messages'
                    and policyname = 'deposer un message') then
    execute 'create policy "deposer un message" on asso_messages
               for insert to anon, authenticated
               with check (traite = false)';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant insert on asso_messages to anon';
    execute 'grant usage, select on sequence asso_messages_id_seq to anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant insert on asso_messages to authenticated';
    execute 'grant usage, select on sequence asso_messages_id_seq to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  Garde-fou : pas plus de 3 messages en 10 minutes pour une meme
--  adresse. De quoi arreter un robot sans jamais gener une personne.
-- ---------------------------------------------------------------------
create or replace function asso_messages_garde()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  select count(*) into v_n
    from asso_messages m
   where lower(m.email) = lower(new.email)
     and m.cree_le > now() - interval '10 minutes';

  if v_n >= 3 then
    raise exception 'trop de messages en peu de temps'
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

drop trigger if exists asso_messages_garde_trig on asso_messages;
create trigger asso_messages_garde_trig
  before insert on asso_messages
  for each row execute function asso_messages_garde();


-- ---------------------------------------------------------------------
--  Vous prevenir par courriel, sans jamais bloquer l'envoi.
--  Si l'alerte echoue, le message reste conserve : rien ne se perd.
-- ---------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net indisponible : les alertes par courriel seront inactives (%)', sqlerrm;
end $$;

create or replace function asso_message_alerte()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform net.http_post(
    url     := 'https://gkineosvtpswcbflqvyu.supabase.co/functions/v1/courrier',
    headers := jsonb_build_object(
                 'Content-Type',   'application/json',
                 'x-alerte-jeton', '8cvglXmMDxg-06FPFQheRRHc-F3kj3L8'),
    body    := jsonb_build_object(
                 'id',      new.id,
                 'nom',     new.nom,
                 'email',   new.email,
                 'sujet',   new.sujet,
                 'message', new.message,
                 'langue',  new.langue,
                 'cree_le', new.cree_le)
  );
  return new;
exception when others then
  begin
    insert into asso_incidents (ou, details, contexte)
    values ('asso_message_alerte', sqlerrm, new.email);
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists asso_message_alerte_trig on asso_messages;
create trigger asso_message_alerte_trig
  after insert on asso_messages
  for each row execute function asso_message_alerte();


-- ---------------------------------------------------------------------
--  Lire son courrier, et marquer un message comme traite.
--  Reserve a la moderation.
-- ---------------------------------------------------------------------
create or replace function asso_messages_liste(p_tout boolean default false)
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
    'attente', (select count(*) from asso_messages where traite = false),
    'liste', coalesce((
      select jsonb_agg(x order by x->>'cree_le' desc)
        from (select jsonb_build_object(
                'id', m.id, 'nom', m.nom, 'email', m.email,
                'sujet', m.sujet, 'message', m.message,
                'langue', m.langue, 'traite', m.traite,
                'cree_le', m.cree_le) as x
                from asso_messages m
               where p_tout or m.traite = false
               order by m.cree_le desc
               limit 200) t), '[]'::jsonb));
end $$;

create or replace function asso_message_traite(p_id bigint, p_traite boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int := 0;
begin
  if not asso_est_admin() then
    return jsonb_build_object('erreur', 'reserve');
  end if;

  update asso_messages
     set traite = p_traite,
         traite_le = case when p_traite then now() else null end
   where id = p_id;

  get diagnostics v_n = row_count;
  return jsonb_build_object('traite', p_traite, 'lignes', v_n);
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_messages_liste(boolean) to authenticated';
    execute 'grant execute on function asso_message_traite(bigint, boolean) to authenticated';
  end if;
end $$;
