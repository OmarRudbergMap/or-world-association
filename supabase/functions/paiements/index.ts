// =====================================================================
//  O.R. WORLD ASSOCIATION - Reception des paiements
//  ---------------------------------------------------------------------
//  Deux adresses :
//     .../paiements/stripe   appelee par Stripe
//     .../paiements/paypal   appelee par PayPal
//
//  Le programme verifie que l'avis vient bien de l'un ou de l'autre,
//  puis demande a la base de creer l'adhesion ou le don.
//
//  auth: "none" : Stripe et PayPal ne possedent aucune cle Supabase,
//  ils doivent donc pouvoir frapper a la porte sans en presenter une.
//  Ce qui les authentifie, c'est leur signature, verifiee plus bas.
// =====================================================================

import { withSupabase } from "npm:@supabase/server@1";

const URL_BASE   = Deno.env.get("SUPABASE_URL") ?? "";
const CLE_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const STRIPE_SECRET_WEBHOOK = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
const PAYPAL_CLIENT_ID      = Deno.env.get("PAYPAL_CLIENT_ID") ?? "";
const PAYPAL_SECRET         = Deno.env.get("PAYPAL_SECRET") ?? "";
const PAYPAL_WEBHOOK_ID     = Deno.env.get("PAYPAL_WEBHOOK_ID") ?? "";
const PAYPAL_RACINE = (Deno.env.get("PAYPAL_ENV") ?? "live") === "sandbox"
  ? "https://api-m.sandbox.paypal.com"
  : "https://api-m.paypal.com";

const MONTANT_ADHESION = Number(Deno.env.get("MONTANT_ADHESION") ?? "12");

// ---------------------------------------------------------------------
//  Petits outils
// ---------------------------------------------------------------------
function reponse(code: number, corps: unknown): Response {
  return new Response(JSON.stringify(corps), {
    status: code,
    headers: { "Content-Type": "application/json" },
  });
}

function hex(octets: ArrayBuffer): string {
  return Array.from(new Uint8Array(octets))
    .map((o) => o.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256(cle: string, message: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(cle),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(message)));
}

// Comparaison a duree constante : on ne laisse rien deviner.
function memeChaine(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// ---------------------------------------------------------------------
//  L'enregistrement en base
// ---------------------------------------------------------------------
type Paiement = {
  fournisseur: string;
  evenement: string;
  genre: string;
  membre: string | null;
  email: string | null;
  prenom: string | null;
  nom: string | null;
  pays: string | null;
  langue: string | null;
  montant: number;
  reference: string | null;
  session: string | null;
  paypal_id: string | null;
  paye_le: string | null;
  charge: unknown;
};

async function enregistrer(p: Paiement): Promise<unknown> {
  const r = await fetch(`${URL_BASE}/rest/v1/rpc/asso_enregistrer_paiement`, {
    method: "POST",
    headers: {
      "apikey": CLE_SERVICE,
      "Authorization": `Bearer ${CLE_SERVICE}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_fournisseur: p.fournisseur,
      p_evenement: p.evenement,
      p_genre: p.genre,
      p_membre: p.membre,
      p_email: p.email,
      p_prenom: p.prenom,
      p_nom: p.nom,
      p_pays: p.pays,
      p_langue: p.langue,
      p_montant: p.montant,
      p_reference: p.reference,
      p_session: p.session,
      p_paypal_id: p.paypal_id,
      p_paye_le: p.paye_le,
      p_charge: p.charge,
    }),
  });
  const texte = await r.text();
  if (!r.ok) throw new Error(`base ${r.status} : ${texte}`);
  try { return JSON.parse(texte); } catch { return texte; }
}

// Un identifiant peut arriver sous la forme "adhesion:uuid" ou "don:uuid".
function lireReference(valeur: string | null | undefined):
  { genre: string | null; membre: string | null } {
  if (!valeur) return { genre: null, membre: null };
  const v = String(valeur).trim();
  const coupe = v.indexOf(":");
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (coupe > 0) {
    const g = v.slice(0, coupe).toLowerCase();
    const m = v.slice(coupe + 1).trim();
    return {
      genre: (g === "adhesion" || g === "don") ? g : null,
      membre: uuid.test(m) ? m : null,
    };
  }
  return { genre: null, membre: uuid.test(v) ? v : null };
}

function coupeNom(complet: string | null | undefined):
  { prenom: string | null; nom: string | null } {
  if (!complet) return { prenom: null, nom: null };
  const bouts = String(complet).trim().split(/\s+/);
  if (bouts.length === 1) return { prenom: bouts[0], nom: null };
  return { prenom: bouts[0], nom: bouts.slice(1).join(" ") };
}

// =====================================================================
//  STRIPE
// =====================================================================
async function signatureStripeValide(corps: string, entete: string | null): Promise<boolean> {
  if (!entete || !STRIPE_SECRET_WEBHOOK) return false;

  let horodatage = "";
  const signatures: string[] = [];
  for (const bout of entete.split(",")) {
    const [cle, valeur] = bout.split("=", 2);
    if (cle?.trim() === "t") horodatage = valeur ?? "";
    if (cle?.trim() === "v1" && valeur) signatures.push(valeur);
  }
  if (!horodatage || signatures.length === 0) return false;

  // Un avis de plus de cinq minutes est refuse : cela empeche
  // qu'un ancien message soit rejoue par quelqu'un d'autre.
  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(horodatage));
  if (!Number.isFinite(age) || age > 300) return false;

  const attendue = await hmacSha256(STRIPE_SECRET_WEBHOOK, `${horodatage}.${corps}`);
  return signatures.some((s) => memeChaine(s, attendue));
}

async function traiteStripe(req: Request): Promise<Response> {
  const corps = await req.text();

  if (!await signatureStripeValide(corps, req.headers.get("stripe-signature"))) {
    return reponse(401, { erreur: "signature refusee" });
  }

  const evenement = JSON.parse(corps);
  if (evenement.type !== "checkout.session.completed") {
    return reponse(200, { ignore: evenement.type });
  }

  const s = evenement.data?.object ?? {};
  if (s.payment_status && s.payment_status !== "paid") {
    return reponse(200, { ignore: "paiement non abouti" });
  }

  const ref = lireReference(s.client_reference_id);
  const meta = s.metadata ?? {};
  const montant = Number(s.amount_total ?? 0) / 100;

  const genre = ref.genre
    ?? (typeof meta.type === "string" ? meta.type.toLowerCase() : null)
    ?? (Math.abs(montant - MONTANT_ADHESION) < 0.005 ? "adhesion" : "don");

  const d = s.customer_details ?? {};
  const noms = coupeNom(d.name);

  const resultat = await enregistrer({
    fournisseur: "stripe",
    evenement: String(evenement.id),
    genre,
    membre: ref.membre,
    email: d.email ?? s.customer_email ?? null,
    prenom: (typeof meta.prenom === "string" ? meta.prenom : null) ?? noms.prenom,
    nom: (typeof meta.nom === "string" ? meta.nom : null) ?? noms.nom,
    pays: d.address?.country ?? null,
    langue: typeof s.locale === "string" && s.locale !== "auto"
      ? s.locale.slice(0, 2) : null,
    montant,
    reference: String(s.client_reference_id ?? ""),
    session: String(s.id ?? ""),
    paypal_id: null,
    paye_le: new Date(Number(evenement.created ?? Date.now() / 1000) * 1000).toISOString(),
    charge: evenement,
  });

  return reponse(200, { recu: true, resultat });
}

// =====================================================================
//  PAYPAL
// =====================================================================
async function jetonPaypal(): Promise<string> {
  const r = await fetch(`${PAYPAL_RACINE}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      "Authorization": "Basic " + btoa(`${PAYPAL_CLIENT_ID}:${PAYPAL_SECRET}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!r.ok) throw new Error(`jeton PayPal refuse (${r.status})`);
  return (await r.json()).access_token as string;
}

async function signaturePaypalValide(corps: string, req: Request): Promise<boolean> {
  if (!PAYPAL_CLIENT_ID || !PAYPAL_SECRET || !PAYPAL_WEBHOOK_ID) return false;

  const h = (n: string) => req.headers.get(n) ?? "";
  const necessaires = ["paypal-transmission-id", "paypal-transmission-time",
                       "paypal-transmission-sig", "paypal-cert-url", "paypal-auth-algo"];
  if (necessaires.some((n) => !h(n))) return false;

  const jeton = await jetonPaypal();
  const r = await fetch(`${PAYPAL_RACINE}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${jeton}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      auth_algo: h("paypal-auth-algo"),
      cert_url: h("paypal-cert-url"),
      transmission_id: h("paypal-transmission-id"),
      transmission_sig: h("paypal-transmission-sig"),
      transmission_time: h("paypal-transmission-time"),
      webhook_id: PAYPAL_WEBHOOK_ID,
      webhook_event: JSON.parse(corps),
    }),
  });
  if (!r.ok) return false;
  return (await r.json()).verification_status === "SUCCESS";
}

// L'avis de capture ne porte pas toujours l'adresse du payeur :
// on va alors la chercher sur la commande.
async function payeurPaypal(res: Record<string, unknown>):
  Promise<{ email: string | null; prenom: string | null; nom: string | null;
            pays: string | null; custom: string | null }> {
  const p = (res.payer ?? {}) as Record<string, any>;
  let email: string | null = p.email_address ?? null;
  let prenom: string | null = p.name?.given_name ?? null;
  let nom: string | null = p.name?.surname ?? null;
  let pays: string | null = p.address?.country_code ?? null;
  let custom: string | null = (res.custom_id as string) ?? null;

  if (email) return { email, prenom, nom, pays, custom };

  const lies = (res.supplementary_data as any)?.related_ids ?? {};
  const commande = lies.order_id;
  if (!commande) return { email, prenom, nom, pays, custom };

  try {
    const jeton = await jetonPaypal();
    const r = await fetch(`${PAYPAL_RACINE}/v2/checkout/orders/${commande}`, {
      headers: { "Authorization": `Bearer ${jeton}` },
    });
    if (!r.ok) return { email, prenom, nom, pays, custom };
    const c = await r.json();
    email  = c.payer?.email_address ?? email;
    prenom = c.payer?.name?.given_name ?? prenom;
    nom    = c.payer?.name?.surname ?? nom;
    pays   = c.payer?.address?.country_code ?? pays;
    custom = c.purchase_units?.[0]?.custom_id ?? custom;
  } catch (_e) { /* on garde ce qu'on a */ }

  return { email, prenom, nom, pays, custom };
}

async function traitePaypal(req: Request): Promise<Response> {
  const corps = await req.text();

  if (!await signaturePaypalValide(corps, req)) {
    return reponse(401, { erreur: "signature refusee" });
  }

  const evenement = JSON.parse(corps);
  if (evenement.event_type !== "PAYMENT.CAPTURE.COMPLETED") {
    return reponse(200, { ignore: evenement.event_type });
  }

  const res = evenement.resource ?? {};
  const montant = Number(res.amount?.value ?? 0);
  const payeur = await payeurPaypal(res);
  const ref = lireReference(payeur.custom);

  const genre = ref.genre
    ?? (Math.abs(montant - MONTANT_ADHESION) < 0.005 ? "adhesion" : "don");

  const resultat = await enregistrer({
    fournisseur: "paypal",
    evenement: String(evenement.id),
    genre,
    membre: ref.membre,
    email: payeur.email,
    prenom: payeur.prenom,
    nom: payeur.nom,
    pays: payeur.pays,
    langue: null,
    montant,
    reference: payeur.custom,
    session: null,
    paypal_id: String(res.id ?? ""),
    paye_le: res.create_time ?? evenement.create_time ?? null,
    charge: evenement,
  });

  return reponse(200, { recu: true, resultat });
}

// =====================================================================
//  L'aiguillage
// =====================================================================
export const gestionnaire = async (req: Request): Promise<Response> => {
  const chemin = new URL(req.url).pathname.replace(/\/+$/, "").split("/").pop();

  if (req.method === "GET" && chemin === "sante") {
    return reponse(200, { etat: "en ligne" });
  }
  if (req.method !== "POST") {
    return reponse(405, { erreur: "methode refusee" });
  }

  try {
    if (chemin === "stripe") return await traiteStripe(req);
    if (chemin === "paypal") return await traitePaypal(req);
    return reponse(404, { erreur: "adresse inconnue", chemin });
  } catch (e) {
    console.error("paiement en echec :", e instanceof Error ? e.message : e);
    // On repond 500 : Stripe et PayPal reessaieront d'eux-memes.
    return reponse(500, { erreur: e instanceof Error ? e.message : "erreur" });
  }
};

export default {
  fetch: withSupabase({ auth: "none" }, gestionnaire),
};
