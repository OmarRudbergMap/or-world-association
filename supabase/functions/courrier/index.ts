/* =====================================================================
   O.R. WORLD ASSOCIATION
   COURRIER : vous prevenir quand un fan ecrit depuis la page Contact.

   Le message est deja conserve dans la base avant d'arriver ici.
   Ce programme ne fait qu'une chose : vous l'envoyer par courriel.
   S'il echoue, le message reste dans la page Moderation : rien ne se
   perd jamais.
   ===================================================================== */

import { withSupabase } from "npm:@supabase/server@1";

const DESTINATAIRE = "orworldassociation@gmail.com";
const EXPEDITEUR = Deno.env.get("COURRIER_EXPEDITEUR") ?? "O.R. World Association <onboarding@resend.dev>";

interface Message {
  id?: number;
  nom?: string;
  email?: string;
  sujet?: string | null;
  message?: string;
  langue?: string | null;
  cree_le?: string;
}

/** Le texte brut d'une personne ne doit jamais devenir du code dans un
 *  courriel : on neutralise les caracteres qui ouvrent des balises. */
export function neutralise(t: unknown): string {
  return String(t ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function corps(m: Message): string {
  const quand = m.cree_le
    ? new Date(m.cree_le).toLocaleString("fr-FR", { timeZone: "Europe/Paris" })
    : "";

  return `<div style="font-family:system-ui,-apple-system,Segoe UI,sans-serif;max-width:560px">
  <p style="color:#6b7280;font-size:13px;margin:0 0 18px">
    Nouveau message depuis la page Contact du site${quand ? " · " + neutralise(quand) : ""}
  </p>
  <table style="width:100%;border-collapse:collapse;font-size:14px">
    <tr><td style="padding:4px 0;color:#6b7280;width:90px">De</td>
        <td style="padding:4px 0"><b>${neutralise(m.nom)}</b></td></tr>
    <tr><td style="padding:4px 0;color:#6b7280">Adresse</td>
        <td style="padding:4px 0"><a href="mailto:${neutralise(m.email)}">${neutralise(m.email)}</a></td></tr>
    ${m.sujet ? `<tr><td style="padding:4px 0;color:#6b7280">Sujet</td>
        <td style="padding:4px 0">${neutralise(m.sujet)}</td></tr>` : ""}
    ${m.langue ? `<tr><td style="padding:4px 0;color:#6b7280">Langue</td>
        <td style="padding:4px 0">${neutralise(m.langue)}</td></tr>` : ""}
  </table>
  <div style="margin:18px 0;padding:16px 18px;background:#f6f5fb;border-left:3px solid #a78bfa;
              border-radius:8px;white-space:pre-wrap;font-size:14px;line-height:1.7">${neutralise(m.message)}</div>
  <p style="color:#6b7280;font-size:12px;margin:18px 0 0">
    Répondez directement à ce courriel pour écrire à ${neutralise(m.nom)}.
    Le message est aussi dans votre page Modération.
  </p>
</div>`;
}

export async function gestionnaire(requete: Request): Promise<Response> {
  if (requete.method !== "POST") {
    return new Response("methode non acceptee", { status: 405 });
  }

  /* Seule votre base peut declencher un envoi. */
  const attendu = Deno.env.get("ALERTE_JETON");
  if (attendu) {
    const recu = requete.headers.get("x-alerte-jeton") ?? "";
    if (recu !== attendu) {
      return new Response("jeton refuse", { status: 401 });
    }
  }

  let m: Message;
  try {
    m = await requete.json();
  } catch {
    return new Response("corps illisible", { status: 400 });
  }

  if (!m || !m.message || !m.email) {
    return new Response("message incomplet", { status: 400 });
  }

  const cle = Deno.env.get("RESEND_API_KEY");
  if (!cle) {
    console.error("RESEND_API_KEY absente : aucun courriel envoye");
    return new Response(JSON.stringify({ envoye: false, raison: "cle absente" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const sujet = m.sujet
    ? `[Site] ${m.sujet} — ${m.nom ?? ""}`.trim()
    : `[Site] Message de ${m.nom ?? "un visiteur"}`;

  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${cle}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: EXPEDITEUR,
        to: [DESTINATAIRE],
        reply_to: m.email,
        subject: sujet,
        html: corps(m),
      }),
    });

    if (!r.ok) {
      const detail = await r.text();
      console.error("Resend a refuse :", r.status, detail);
      return new Response(JSON.stringify({ envoye: false, statut: r.status }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ envoye: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("envoi impossible :", e);
    return new Response(JSON.stringify({ envoye: false }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
}

export default {
  fetch: withSupabase({ auth: "none" }, gestionnaire),
};
