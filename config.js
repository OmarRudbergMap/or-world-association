/* =====================================================================
   O.R. WORLD ASSOCIATION — CONNEXION À LA BASE DE DONNÉES
   ---------------------------------------------------------------------
   Ces deux valeurs sont publiques par nature : elles peuvent figurer
   dans le site sans aucun risque. La clé secrète (service_role) ne doit
   JAMAIS être écrite ici.
   ===================================================================== */

const SUPABASE_URL = "https://gkineosvtpswcbflqvyu.supabase.co";
const SUPABASE_CLE = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdraW5lb3N2dHBzd2NiZmxxdnl1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4OTc3NzksImV4cCI6MjEwNTQ3Mzc3OX0.AO20otlLmN0Vb003dJxSlp8nahYnz9txJ476cvmAhNQ";

let db = null;
if (window.supabase && window.supabase.createClient) {
  db = window.supabase.createClient(SUPABASE_URL, SUPABASE_CLE);
} else {
  console.warn("La bibliothèque Supabase n'a pas pu se charger.");
}

/* ---------------------------------------------------------------------
   Petites fonctions utilisées par toutes les pages
   --------------------------------------------------------------------- */

// Qui est connecté ? Renvoie le compte, ou null.
async function compteActuel(){
  const { data } = await db.auth.getUser();
  return data ? data.user : null;
}

// La fiche complète du membre connecté.
async function ficheMembre(){
  const compte = await compteActuel();
  if(!compte) return null;
  const { data, error } = await db
    .from("asso_membres")
    .select("*")
    .eq("id", compte.id)
    .single();
  if(error) return null;
  return data;
}

// Les adhésions du membre connecté, de la plus récente à la plus ancienne.
async function mesAdhesions(){
  const compte = await compteActuel();
  if(!compte) return [];
  const { data } = await db
    .from("asso_adhesions")
    .select("*")
    .eq("membre", compte.id)
    .order("annee", { ascending:false });
  return data || [];
}

// Adhésion à jour pour l'année en cours ?
async function adhesionAJour(){
  const liste = await mesAdhesions();
  const annee = new Date().getFullYear();
  return liste.some(function(a){ return a.annee === annee && a.statut === "payee"; });
}

// Protéger une page : renvoie vers la connexion si personne n'est connecté.
async function pageProtegee(){
  const compte = await compteActuel();
  if(!compte){
    window.location.href = "connexion.html?retour=" +
      encodeURIComponent(window.location.pathname.split("/").pop());
    return null;
  }
  return compte;
}

// Se déconnecter.
async function deconnexion(){
  await db.auth.signOut();
  window.location.href = "index.html";
}

// Les compteurs publics du site.
async function compteursPublics(){
  const { data } = await db.from("asso_compteurs").select("*").single();
  return data || {};
}
