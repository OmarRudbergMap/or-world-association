-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  Le moteur des paiements : Stripe et PayPal creent l'adhesion
--  ou le don tout seuls, avec le numero de membre et le numero de recu.
--
--  Ce script ne supprime rien. Il peut etre passe plusieurs fois.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. Le registre des paiements deja recus.
--     Stripe et PayPal renvoient parfois le meme paiement plusieurs
--     fois. Cette table garantit qu'une adhesion n'est jamais creee
--     en double.
-- ---------------------------------------------------------------------
create table if not exists asso_paiements_recus (
  id           bigserial primary key,
  fournisseur  text        not null,
  evenement    text        not null,
  recu_le      timestamptz not null default now(),
  resultat     text,
  charge       jsonb
);

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'asso_paiements_recus_unique') then
    alter table asso_paiements_recus
      add constraint asso_paiements_recus_unique unique (fournisseur, evenement);
  end if;
end $$;

alter table asso_paiements_recus enable row level security;


-- ---------------------------------------------------------------------
--  2. Les paiements qu'on n'a pas su rattacher a un compte du site.
--     Rien ne se perd : le bureau retrouve ici tout ce qui demande
--     une verification humaine.
-- ---------------------------------------------------------------------
create table if not exists asso_paiements_a_rattacher (
  id            bigserial primary key,
  fournisseur   text        not null,
  evenement     text,
  genre         text,
  email         text,
  prenom        text,
  nom           text,
  montant       numeric,
  motif         text,
  recu_le       timestamptz not null default now(),
  traite_le     timestamptz,
  charge        jsonb
);

alter table asso_paiements_a_rattacher enable row level security;


-- ---------------------------------------------------------------------
--  3. Le coeur : enregistrer un paiement.
--
--     Appele uniquement par la fonction Edge, avec la cle de service.
--     Renvoie un petit compte rendu en jsonb.
-- ---------------------------------------------------------------------
create or replace function asso_enregistrer_paiement(
  p_fournisseur text,
  p_evenement   text,
  p_genre       text,
  p_membre      uuid,
  p_email       text,
  p_prenom      text,
  p_nom         text,
  p_pays        text,
  p_langue      text,
  p_montant     numeric,
  p_reference   text,
  p_session     text,
  p_paypal_id   text,
  p_paye_le     timestamptz,
  p_charge      jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deja       int;
  v_membre     uuid := p_membre;
  v_email      text := lower(nullif(trim(p_email), ''));
  v_paye       timestamptz := coalesce(p_paye_le, now());
  v_debut      date;
  v_fin        date;
  v_annee      int;
  v_num        int;
  v_suite      int;
  v_recu       text;
  v_existe     bigint;
  v_id         bigint;
  v_genre      text := coalesce(nullif(trim(p_genre), ''), 'adhesion');
begin
  -- --- le meme paiement ne passe qu'une fois -------------------------
  insert into asso_paiements_recus (fournisseur, evenement, charge)
  values (p_fournisseur, p_evenement, p_charge)
  on conflict (fournisseur, evenement) do nothing;

  get diagnostics v_deja = row_count;
  if v_deja = 0 then
    return jsonb_build_object('statut', 'deja_traite', 'evenement', p_evenement);
  end if;

  -- --- les numeros se calculent un a la fois -------------------------
  perform pg_advisory_xact_lock(hashtext('asso_numerotation'));

  -- --- retrouver le compte du site -----------------------------------
  if v_membre is null and v_email is not null then
    select m.id into v_membre
      from asso_membres m
     where lower(m.email) = v_email
     limit 1;
  end if;

  -- =====================  UN DON  ====================================
  if v_genre = 'don' then
    v_annee := extract(year from (v_paye at time zone 'Europe/Paris'))::int;

    select coalesce(max((substring(d.numero_recu from '[0-9]+$'))::int), 0) + 1
      into v_suite
      from asso_dons d
     where d.numero_recu like 'DON-' || v_annee || '-%';

    v_recu := 'DON-' || v_annee || '-' || lpad(v_suite::text, 3, '0');

    insert into asso_dons (membre, prenom, nom, email, pays, langue,
                           montant, moyen, origine, statut, numero_recu,
                           fait_le, stripe_session, paypal_id)
    values (v_membre, p_prenom, p_nom, v_email, p_pays, p_langue,
            p_montant, p_fournisseur, p_fournisseur, 'recu', v_recu,
            (v_paye at time zone 'Europe/Paris')::date, p_session, p_paypal_id)
    returning id into v_id;

    update asso_paiements_recus
       set resultat = 'don ' || v_recu
     where fournisseur = p_fournisseur and evenement = p_evenement;

    if v_membre is null then
      insert into asso_paiements_a_rattacher
        (fournisseur, evenement, genre, email, prenom, nom, montant, motif, charge)
      values (p_fournisseur, p_evenement, 'don', v_email, p_prenom, p_nom,
              p_montant, 'aucun compte du site avec cette adresse', p_charge);
    end if;

    return jsonb_build_object('statut', 'don_cree', 'id', v_id,
                              'numero_recu', v_recu, 'membre', v_membre);
  end if;

  -- =====================  UNE ADHESION  ==============================
  -- Elle compte a partir du premier jour du mois du paiement,
  -- et dure un an : payee le 17/04/2026, elle va du 01/04/2026
  -- au 31/03/2027.
  v_debut := date_trunc('month', (v_paye at time zone 'Europe/Paris'))::date;
  v_fin   := (v_debut + interval '1 year' - interval '1 day')::date;
  v_annee := extract(year from v_debut)::int;

  -- --- deja enregistree ? --------------------------------------------
  select a.id into v_existe
    from asso_adhesions a
   where lower(a.email) = v_email
     and a.date_debut = v_debut
   limit 1;

  if v_existe is not null then
    update asso_adhesions
       set membre         = coalesce(membre, v_membre),
           montant        = coalesce(montant, p_montant),
           moyen          = coalesce(moyen, p_fournisseur),
           statut         = 'actif',
           stripe_session = coalesce(stripe_session, p_session),
           paypal_id      = coalesce(paypal_id, p_paypal_id),
           paye_le        = coalesce(paye_le, v_paye),
           reference      = coalesce(reference, p_reference)
     where id = v_existe;

    update asso_paiements_recus
       set resultat = 'adhesion deja presente, completee'
     where fournisseur = p_fournisseur and evenement = p_evenement;

    return jsonb_build_object('statut', 'adhesion_completee', 'id', v_existe);
  end if;

  -- --- le numero de membre, le meme toute la vie ----------------------
  select max(a.numero_membre) into v_num
    from asso_adhesions a
   where (v_membre is not null and a.membre = v_membre)
      or (v_email is not null and lower(a.email) = v_email);

  if v_num is null then
    select coalesce(max(a.numero_membre), 0) + 1 into v_num from asso_adhesions a;
  end if;

  -- --- le numero de recu, suite par annee -----------------------------
  select coalesce(max((substring(a.numero_recu from '[0-9]+$'))::int), 0) + 1
    into v_suite
    from asso_adhesions a
   where a.numero_recu like 'ADH-' || v_annee || '-%';

  v_recu := 'ADH-' || v_annee || '-' || lpad(v_suite::text, 3, '0');

  insert into asso_adhesions (membre, numero_membre, prenom, nom, email, pays,
                              langue, annee, date_debut, date_fin, montant, don,
                              moyen, origine, statut, reference, numero_recu,
                              stripe_session, paypal_id, paye_le)
  values (v_membre, v_num, p_prenom, p_nom, v_email, p_pays,
          p_langue, v_annee, v_debut, v_fin, p_montant, 0,
          p_fournisseur, p_fournisseur, 'actif', p_reference, v_recu,
          p_session, p_paypal_id, v_paye)
  returning id into v_id;

  update asso_paiements_recus
     set resultat = 'adhesion ' || v_recu
   where fournisseur = p_fournisseur and evenement = p_evenement;

  if v_membre is null then
    insert into asso_paiements_a_rattacher
      (fournisseur, evenement, genre, email, prenom, nom, montant, motif, charge)
    values (p_fournisseur, p_evenement, 'adhesion', v_email, p_prenom, p_nom,
            p_montant, 'aucun compte du site avec cette adresse', p_charge);
  end if;

  return jsonb_build_object('statut', 'adhesion_creee', 'id', v_id,
                            'numero_membre', v_num, 'numero_recu', v_recu,
                            'date_debut', v_debut, 'date_fin', v_fin,
                            'membre', v_membre);
end $$;

-- Personne ne peut appeler cette fonction depuis le site : elle est
-- reservee a la cle de service, celle que seul le programme possede.
do $$
begin
  execute 'revoke all on function asso_enregistrer_paiement('
       || 'text, text, text, uuid, text, text, text, text, text,'
       || 'numeric, text, text, text, timestamptz, jsonb) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function asso_enregistrer_paiement('
         || 'text, text, text, uuid, text, text, text, text, text,'
         || 'numeric, text, text, text, timestamptz, jsonb) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function asso_enregistrer_paiement('
         || 'text, text, text, uuid, text, text, text, text, text,'
         || 'numeric, text, text, text, timestamptz, jsonb) from authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  4. Quand une personne cree enfin son compte, ses adhesions
--     payees avant se rattachent toutes seules a ce compte.
-- ---------------------------------------------------------------------
create or replace function asso_rattacher_mes_adhesions()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_n     int;
begin
  if auth.uid() is null then
    return jsonb_build_object('statut', 'non_connecte');
  end if;

  select lower(m.email) into v_email from asso_membres m where m.id = auth.uid();
  if v_email is null then
    return jsonb_build_object('statut', 'pas_de_fiche');
  end if;

  update asso_adhesions set membre = auth.uid()
   where membre is null and lower(email) = v_email;
  get diagnostics v_n = row_count;

  update asso_dons set membre = auth.uid()
   where membre is null and lower(email) = v_email;

  update asso_paiements_a_rattacher set traite_le = now()
   where traite_le is null and lower(email) = v_email;

  return jsonb_build_object('statut', 'ok', 'adhesions_rattachees', v_n);
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function asso_rattacher_mes_adhesions() to authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------------
--  5. Le tableau du bureau : ce qui demande une verification.
-- ---------------------------------------------------------------------
create or replace view asso_paiements_en_attente as
  select r.id, r.fournisseur, r.genre, r.email, r.prenom, r.nom,
         r.montant, r.motif, r.recu_le
    from asso_paiements_a_rattacher r
   where r.traite_le is null
   order by r.recu_le desc;
