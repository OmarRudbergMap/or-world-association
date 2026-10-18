-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES RAPPELS D'ECHEANCE D'ADHESION, ENVOYES TOUT SEULS PAR BREVO
--  ---------------------------------------------------------------
--  A executer APRES avoir active pg_cron et pg_net dans
--  Database > Extensions, et APRES avoir range la cle Brevo
--  dans le coffre (voir le bloc separe).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LA LANGUE DE CHAQUE ADHERENT
--    Chacun doit recevoir le rappel dans sa langue. On la devine a
--    partir du pays, et vous pourrez corriger a la main si besoin.
-- ---------------------------------------------------------------------
alter table asso_adhesions add column if not exists langue text;

update asso_adhesions set langue =
  case pays
    when 'France'     then 'fr'
    when 'Canada'     then 'fr'
    when 'Espagne'    then 'es'
    when 'Suède'      then 'sv'
    when 'Autriche'   then 'de'
    when 'Allemagne'  then 'de'
    when 'Portugal'   then 'pt'
    when 'Brésil'     then 'pt'
    else 'en'
  end
where langue is null;


-- ---------------------------------------------------------------------
-- 2. LES TEXTES DES MESSAGES
--    Dans une table a part, pour que vous puissiez les modifier plus
--    tard sans toucher au reste. Trois moments, six langues.
--    {prenom} et {date} sont remplaces automatiquement.
-- ---------------------------------------------------------------------
create table if not exists asso_textes_mail (
  cle    text not null,
  langue text not null,
  sujet  text not null,
  corps  text not null,
  primary key (cle, langue)
);

alter table asso_textes_mail enable row level security;

insert into asso_textes_mail (cle, langue, sujet, corps) values
-- ---------- a 30 jours
('relance30','fr','Votre adhésion arrive à échéance dans un mois',
 'Bonjour {prenom},<br><br>Votre adhésion à O.R. World Association se termine le <b>{date}</b>, dans un mois.<br><br>Si vous souhaitez rester adhérente ou adhérent, vous pouvez la renouveler depuis votre espace sur le site. Si vous préférez ne pas renouveler, vous n''avez rien à faire, et vous restez bien sûr la bienvenue dans tout ce que nous organisons.<br><br>Merci d''être avec nous.<br>O.R. World Association'),
('relance30','en','Your membership ends in one month',
 'Hello {prenom},<br><br>Your membership of O.R. World Association ends on <b>{date}</b>, one month from now.<br><br>If you would like to stay a member, you can renew from your account on the website. If you would rather not renew, there is nothing to do, and you remain very welcome in everything we organise.<br><br>Thank you for being with us.<br>O.R. World Association'),
('relance30','es','Tu afiliación termina dentro de un mes',
 'Hola {prenom},<br><br>Tu afiliación a O.R. World Association termina el <b>{date}</b>, dentro de un mes.<br><br>Si quieres seguir siendo socia o socio, puedes renovarla desde tu cuenta en la web. Si prefieres no renovar, no tienes que hacer nada, y sigues siendo bienvenida en todo lo que organizamos.<br><br>Gracias por estar con nosotros.<br>O.R. World Association'),
('relance30','sv','Ditt medlemskap går ut om en månad',
 'Hej {prenom},<br><br>Ditt medlemskap i O.R. World Association går ut den <b>{date}</b>, om en månad.<br><br>Vill du fortsätta vara medlem kan du förnya från ditt konto på webbplatsen. Vill du hellre inte förnya behöver du inte göra något, och du är förstås lika välkommen i allt vi ordnar.<br><br>Tack för att du är med oss.<br>O.R. World Association'),
('relance30','de','Eure Mitgliedschaft endet in einem Monat',
 'Hallo {prenom},<br><br>Eure Mitgliedschaft bei O.R. World Association endet am <b>{date}</b>, in einem Monat.<br><br>Wenn ihr Mitglied bleiben möchtet, könnt ihr sie über euer Konto auf der Website verlängern. Wenn ihr lieber nicht verlängert, müsst ihr nichts tun, und ihr seid bei allem, was wir organisieren, weiterhin herzlich willkommen.<br><br>Danke, dass ihr dabei seid.<br>O.R. World Association'),
('relance30','pt','A sua adesão termina dentro de um mês',
 'Olá {prenom},<br><br>A sua adesão à O.R. World Association termina a <b>{date}</b>, dentro de um mês.<br><br>Se quiser continuar como associada ou associado, pode renovar a partir da sua conta no site. Se preferir não renovar, não tem nada a fazer, e continua muito bem-vinda em tudo o que organizamos.<br><br>Obrigada por estar connosco.<br>O.R. World Association'),

-- ---------- a 7 jours
('relance7','fr','Plus qu''une semaine pour renouveler votre adhésion',
 'Bonjour {prenom},<br><br>Petit rappel : votre adhésion se termine le <b>{date}</b>, dans une semaine.<br><br>Le renouvellement se fait en quelques clics depuis votre espace sur le site.<br><br>À bientôt.<br>O.R. World Association'),
('relance7','en','One week left to renew your membership',
 'Hello {prenom},<br><br>A short reminder: your membership ends on <b>{date}</b>, one week from now.<br><br>Renewing takes a few clicks from your account on the website.<br><br>See you soon.<br>O.R. World Association'),
('relance7','es','Queda una semana para renovar tu afiliación',
 'Hola {prenom},<br><br>Un recordatorio: tu afiliación termina el <b>{date}</b>, dentro de una semana.<br><br>Renovar son unos pocos clics desde tu cuenta en la web.<br><br>Hasta pronto.<br>O.R. World Association'),
('relance7','sv','En vecka kvar att förnya ditt medlemskap',
 'Hej {prenom},<br><br>En liten påminnelse: ditt medlemskap går ut den <b>{date}</b>, om en vecka.<br><br>Att förnya tar några klick från ditt konto på webbplatsen.<br><br>Vi hörs snart.<br>O.R. World Association'),
('relance7','de','Noch eine Woche, um eure Mitgliedschaft zu verlängern',
 'Hallo {prenom},<br><br>Eine kurze Erinnerung: eure Mitgliedschaft endet am <b>{date}</b>, in einer Woche.<br><br>Die Verlängerung dauert ein paar Klicks über euer Konto auf der Website.<br><br>Bis bald.<br>O.R. World Association'),
('relance7','pt','Falta uma semana para renovar a sua adesão',
 'Olá {prenom},<br><br>Um pequeno lembrete: a sua adesão termina a <b>{date}</b>, dentro de uma semana.<br><br>Renovar leva uns cliques a partir da sua conta no site.<br><br>Até breve.<br>O.R. World Association'),

-- ---------- le jour meme
('relance0','fr','Votre adhésion se termine aujourd''hui',
 'Bonjour {prenom},<br><br>Votre adhésion à O.R. World Association se termine aujourd''hui, le <b>{date}</b>.<br><br>Vous pouvez la renouveler à tout moment depuis votre espace sur le site, et vous retrouverez votre place exactement comme avant.<br><br>Merci pour cette année avec nous.<br>O.R. World Association'),
('relance0','en','Your membership ends today',
 'Hello {prenom},<br><br>Your membership of O.R. World Association ends today, <b>{date}</b>.<br><br>You can renew at any time from your account on the website, and you will find your place exactly as you left it.<br><br>Thank you for this year with us.<br>O.R. World Association'),
('relance0','es','Tu afiliación termina hoy',
 'Hola {prenom},<br><br>Tu afiliación a O.R. World Association termina hoy, <b>{date}</b>.<br><br>Puedes renovarla cuando quieras desde tu cuenta en la web, y recuperarás tu sitio tal cual.<br><br>Gracias por este año con nosotros.<br>O.R. World Association'),
('relance0','sv','Ditt medlemskap går ut i dag',
 'Hej {prenom},<br><br>Ditt medlemskap i O.R. World Association går ut i dag, den <b>{date}</b>.<br><br>Du kan förnya när som helst från ditt konto på webbplatsen, och du får tillbaka din plats precis som den var.<br><br>Tack för det här året med oss.<br>O.R. World Association'),
('relance0','de','Eure Mitgliedschaft endet heute',
 'Hallo {prenom},<br><br>Eure Mitgliedschaft bei O.R. World Association endet heute, am <b>{date}</b>.<br><br>Ihr könnt sie jederzeit über euer Konto auf der Website verlängern, und ihr findet euren Platz genauso wieder vor.<br><br>Danke für dieses Jahr mit uns.<br>O.R. World Association'),
('relance0','pt','A sua adesão termina hoje',
 'Olá {prenom},<br><br>A sua adesão à O.R. World Association termina hoje, <b>{date}</b>.<br><br>Pode renovar quando quiser a partir da sua conta no site, e encontra o seu lugar tal como estava.<br><br>Obrigada por este ano connosco.<br>O.R. World Association')
on conflict (cle, langue) do nothing;


-- ---------------------------------------------------------------------
-- 3. L'HABILLAGE DU MESSAGE
--    Le texte est pose dans une mise en page simple aux couleurs de
--    l'association, lisible partout, y compris sur telephone.
-- ---------------------------------------------------------------------
create or replace function asso_habiller_mail(corps text)
returns text
language sql
immutable
as $$
  select
  '<div style="margin:0;padding:24px 12px;background:#f4f1fb;font-family:Helvetica,Arial,sans-serif">'
  '<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;'
  'box-shadow:0 2px 14px rgba(90,60,150,.12)">'
  '<div style="background:#dbb3e5;padding:22px 26px;text-align:center">'
  '<div style="font-size:19px;letter-spacing:.06em;color:#5b3ea8;font-weight:bold">O.R. WORLD ASSOCIATION</div>'
  '<div style="font-size:11px;letter-spacing:.18em;color:#7b61c4;margin-top:5px">LOI 1901, À BUT NON LUCRATIF</div>'
  '</div>'
  '<div style="padding:28px 26px;font-size:15px;line-height:1.65;color:#2f2a44">' || corps || '</div>'
  '<div style="padding:16px 26px 24px;border-top:1px solid #ece6f8;font-size:12px;line-height:1.6;color:#8d80ae;text-align:center">'
  'www.orworldassociation.com<br>orworldassociation@gmail.com'
  '</div></div></div>';
$$;


-- ---------------------------------------------------------------------
-- 4. LA FONCTION QUI ENVOIE
--    Elle regarde qui arrive a echeance, prend le texte dans la bonne
--    langue, envoie par Brevo, et note la date d'envoi pour ne jamais
--    envoyer deux fois le meme rappel.
-- ---------------------------------------------------------------------
create or replace function asso_envoyer_relances()
returns table (destinataire text, etape text)
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  cle_api text;
  r     record;
  pas   text;
  t     record;
  jours int;
begin
  select decrypted_secret into cle_api
    from vault.decrypted_secrets where name = 'brevo_api_key';
  if cle_api is null then
    raise exception 'La cle Brevo est absente du coffre (nom attendu : brevo_api_key)';
  end if;

  for r in
    select * from asso_adhesions
     where email is not null and date_fin is not null
  loop
    jours := r.date_fin - current_date;
    pas := null;
    if jours between 28 and 32 and r.relance_30 is null then pas := 'relance30';
    elsif jours between  5 and  9 and r.relance_7  is null then pas := 'relance7';
    elsif jours between -1 and  0 and r.relance_0  is null then pas := 'relance0';
    end if;
    continue when pas is null;

    select * into t from asso_textes_mail
     where cle = pas and langue = coalesce(r.langue, 'en');
    if not found then
      select * into t from asso_textes_mail where cle = pas and langue = 'en';
    end if;

    perform net.http_post(
      url     := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object(
                   'api-key', cle_api,
                   'accept', 'application/json',
                   'content-type', 'application/json'),
      body    := jsonb_build_object(
                   'sender', jsonb_build_object(
                       'name',  'O.R. World Association',
                       'email', 'orworldassociation@gmail.com'),
                   'to', jsonb_build_array(jsonb_build_object(
                       'email', r.email,
                       'name',  coalesce(r.prenom, '') || ' ' || coalesce(r.nom, ''))),
                   'subject', t.sujet,
                   'htmlContent', asso_habiller_mail(
                       replace(replace(t.corps,
                         '{prenom}', coalesce(r.prenom, '')),
                         '{date}',   to_char(r.date_fin, 'DD/MM/YYYY')))),
      timeout_milliseconds := 8000
    );

    if    pas = 'relance30' then update asso_adhesions set relance_30 = now() where id = r.id;
    elsif pas = 'relance7'  then update asso_adhesions set relance_7  = now() where id = r.id;
    else                         update asso_adhesions set relance_0  = now() where id = r.id;
    end if;

    destinataire := r.email;
    etape := pas;
    return next;
  end loop;
end;
$$;

revoke all on function asso_envoyer_relances() from anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. UN ENVOI D'ESSAI
--    Envoie un faux rappel a l'adresse que vous indiquez, pour verifier
--    que tout fonctionne avant de laisser tourner la machine.
-- ---------------------------------------------------------------------
create or replace function asso_mail_essai(adresse text, langue text default 'fr')
returns text
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare cle_api text; t record;
begin
  select decrypted_secret into cle_api
    from vault.decrypted_secrets where name = 'brevo_api_key';
  if cle_api is null then return 'La cle Brevo est absente du coffre.'; end if;

  select * into t from asso_textes_mail where cle = 'relance30' and asso_textes_mail.langue = asso_mail_essai.langue;
  if not found then return 'Texte introuvable pour cette langue.'; end if;

  perform net.http_post(
    url     := 'https://api.brevo.com/v3/smtp/email',
    headers := jsonb_build_object('api-key', cle_api, 'accept', 'application/json',
                                  'content-type', 'application/json'),
    body    := jsonb_build_object(
                 'sender', jsonb_build_object('name','O.R. World Association',
                                              'email','orworldassociation@gmail.com'),
                 'to', jsonb_build_array(jsonb_build_object('email', adresse)),
                 'subject', '[ESSAI] ' || t.sujet,
                 'htmlContent', asso_habiller_mail(
                     replace(replace(t.corps,'{prenom}','Elisabeth'),
                             '{date}', to_char(current_date + 30, 'DD/MM/YYYY')))),
    timeout_milliseconds := 8000);

  return 'Message d''essai parti vers ' || adresse ||
         '. Regardez la boite, et les indesirables.';
end;
$$;

revoke all on function asso_mail_essai(text, text) from anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. LA TACHE QUOTIDIENNE
--    Tous les jours a 9h00 UTC, soit 10h ou 11h en France selon
--    la saison. On supprime d'abord une eventuelle ancienne tache
--    du meme nom, pour pouvoir relancer ce script sans rien doubler.
-- ---------------------------------------------------------------------
do $$
begin
  perform cron.unschedule('relances-adhesions');
exception when others then null;
end $$;

select cron.schedule('relances-adhesions', '0 9 * * *',
                     $job$ select asso_envoyer_relances(); $job$);


-- ---------------------------------------------------------------------
-- 7. VERIFICATION
-- ---------------------------------------------------------------------
select jobname, schedule, active from cron.job where jobname = 'relances-adhesions';

select prenom, nom, pays, langue, date_fin,
       (date_fin - current_date) as jours_restants,
       relance_30, relance_7, relance_0
  from asso_adhesions
 order by date_fin;
