-- =====================================================================
--  O.R. WORLD ASSOCIATION
--  LES DOCUMENTS SIGNES DE L'ADHESION
--
--  Le rangement « documents » existe deja dans votre Supabase et
--  accepte les PDF, les JPG et les PNG. Ce script s'occupe des
--  autorisations : qui a le droit d'y deposer un fichier, et qui a le
--  droit de le relire.
--
--  La regle est simple :
--    · un adherent connecte depose dans un dossier qui porte son
--      propre numero de compte, et nulle part ailleurs ;
--    · il peut relire ses propres documents, jamais ceux des autres ;
--    · le bureau de l'association peut tout relire ;
--    · personne ne peut modifier ni effacer un document deja depose,
--      pas meme celui qui l'a envoye. Une autorisation parentale
--      signee ne doit pas pouvoir disparaitre.
--
--  Ce script ne supprime aucun fichier et peut etre passe plusieurs
--  fois : il remplace les regles, jamais les documents.
-- =====================================================================

-- Le rangement doit exister et rester prive.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documents', 'documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update
   set public             = false,
       file_size_limit    = greatest(coalesce(storage.buckets.file_size_limit, 0), 10485760),
       allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png',
                                  'image/heic', 'image/heif'];
-- heic et heif : les photos prises avec un iPhone. Sans elles, un
-- adherent qui photographie son autorisation signee se voit refuser
-- son fichier sans comprendre pourquoi.


-- ---------------------------------------------------------------------
--  Deposer : uniquement dans son propre dossier.
-- ---------------------------------------------------------------------
drop policy if exists "deposer mes documents" on storage.objects;
create policy "deposer mes documents" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ---------------------------------------------------------------------
--  Relire : les siens, ou tous si l'on est du bureau.
-- ---------------------------------------------------------------------
drop policy if exists "relire mes documents" on storage.objects;
create policy "relire mes documents" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or asso_est_admin()
    )
  );


-- ---------------------------------------------------------------------
--  Verification : ce que ce script vient de mettre en place.
-- ---------------------------------------------------------------------
select p.policyname as regle, p.cmd as action, p.roles as pour_qui
  from pg_policies p
 where p.schemaname = 'storage'
   and p.tablename = 'objects'
   and p.policyname in ('deposer mes documents', 'relire mes documents')
 order by p.policyname;
