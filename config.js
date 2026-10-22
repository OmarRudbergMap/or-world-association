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
  // Indispensable : « let » ne pose pas la variable sur window, et
  // plusieurs pages verifient « window.db » avant de travailler.
  // Sans cette ligne, elles croient toutes que la base est injoignable.
  window.db = db;
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

// ---------------------------------------------------------------------
//  Rattacher les adhesions payees avant la creation du compte.
//  Une personne peut avoir regle sa cotisation, puis creer son compte
//  plus tard, ou venir de l'ancien site. La base retrouve alors ses
//  adhesions grace a son adresse e-mail et les accroche a son compte.
//  L'operation ne fait que remplir une case vide, elle ne cree et ne
//  supprime rien.
// ---------------------------------------------------------------------
let ORW_rattachementFait = false;

async function rattacheMesAdhesions(){
  if(ORW_rattachementFait || !db) return;
  ORW_rattachementFait = true;
  try{ await db.rpc("asso_rattacher_mes_adhesions"); }catch(e){}
}

// a la connexion, et a la creation du compte
if(db && db.auth && db.auth.onAuthStateChange){
  db.auth.onAuthStateChange(function(evenement){
    if(evenement === "SIGNED_IN" || evenement === "USER_UPDATED"){
      ORW_rattachementFait = false;
      rattacheMesAdhesions();
    }
  });
}

// Les adhésions du membre connecté, de la plus récente à la plus ancienne.
async function mesAdhesions(){
  const compte = await compteActuel();
  if(!compte) return [];
  await rattacheMesAdhesions();
  const { data } = await db
    .from("asso_adhesions")
    .select("*")
    .eq("membre", compte.id)
    .order("date_debut", { ascending:false });
  return data || [];
}

// Adhésion encore valable aujourd'hui ?
// Une adhésion court un an à partir du jour du paiement, on regarde donc
// la date de fin et non l'année civile.
async function adhesionAJour(){
  const liste = await mesAdhesions();
  const jour = new Date().toISOString().slice(0,10);
  return liste.some(function(a){ return a.date_fin && a.date_fin >= jour; });
}

// L'adhésion en cours, ou null.
async function adhesionEnCours(){
  const liste = await mesAdhesions();
  const jour = new Date().toISOString().slice(0,10);
  return liste.filter(function(a){ return a.date_fin && a.date_fin >= jour; })
              .sort(function(x,y){ return x.date_fin < y.date_fin ? 1 : -1; })[0] || null;
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
