/* =====================================================================
   O.R. WORLD ASSOCIATION — LE BOUTON DU COMPTE, SUR TOUTES LES PAGES
   ---------------------------------------------------------------------
   Dans l'en-tête, le petit bonhomme rond ne disait rien à personne.
   Ce fichier lui ajoute un mot lisible, et le fait changer tout seul :

     · personne n'est connecté  ->  « Connexion »,  vers connexion.html
     · quelqu'un est connecté   ->  « Mon espace », vers espace.html

   Il n'a besoin de rien d'autre : il reconnaît une session ouverte
   en lisant ce que Supabase range dans le navigateur, sans charger
   la bibliothèque. Il fonctionne donc même sur les pages légères.
   ===================================================================== */
(function () {
  "use strict";

  var MOTS = {
    fr: { entrer: "Connexion", espace: "Mon espace" },
    en: { entrer: "Log in",    espace: "My account" },
    es: { entrer: "Entrar",    espace: "Mi cuenta" },
    sv: { entrer: "Logga in",  espace: "Mitt konto" },
    de: { entrer: "Anmelden",  espace: "Mein Konto" },
    pt: { entrer: "Entrar",    espace: "A minha conta" }
  };

  function langue() {
    var l = null;
    try { l = localStorage.getItem("orw-langue"); } catch (e) {}
    if (!l && window.ORW_LANGUE) l = window.ORW_LANGUE;
    if (!l) l = (document.documentElement.lang || "fr").slice(0, 2);
    return MOTS[l] ? l : "fr";
  }

  /* Une session ouverte ? Supabase garde son jeton dans le navigateur,
     sous une clé du genre « sb-xxxx-auth-token ». On se contente de
     regarder s'il existe et s'il n'est pas périmé. */
  function connecte() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var cle = localStorage.key(i);
        if (!cle || cle.indexOf("sb-") !== 0 || cle.indexOf("auth-token") < 0) continue;
        var brut = localStorage.getItem(cle);
        if (!brut) continue;
        var j = JSON.parse(brut);
        if (!j) continue;
        if (j.expires_at && (j.expires_at * 1000) < Date.now()) continue;
        if (j.access_token || (j.currentSession && j.currentSession.access_token)) return true;
      }
    } catch (e) {}
    return false;
  }

  var STYLE =
    ".rond--compte{width:auto!important;border-radius:999px;padding:0 .85rem 0 .7rem;" +
    "gap:.45rem;display:inline-flex;align-items:center;justify-content:center;" +
    "white-space:nowrap;font-size:.8rem;letter-spacing:.02em;text-decoration:none}" +
    ".rond--compte .mot-compte{display:inline-block;line-height:1}" +
    "@media (max-width:900px){.rond--compte{padding:0;width:34px!important}" +
    ".rond--compte .mot-compte{display:none}}";


  /* ------------------------------------------------------------------
     L'onglet Flashmob porte une pastille NEW : c'est le projet du
     moment, et il vient d'arriver dans le menu de toutes les pages.
     Pour la retirer le jour venu, il suffit de supprimer ce bloc.
     ------------------------------------------------------------------ */
  var STYLE_NEUF =
    ".menu a.onglet-neuf{position:relative;color:#fff}" +
    ".menu a.onglet-neuf .eti-neuf{display:inline-block;margin-left:.4rem;" +
    "font-size:.56rem;font-weight:600;letter-spacing:.1em;line-height:1;" +
    "padding:.22rem .36rem .2rem;border-radius:999px;vertical-align:.18em;" +
    "color:#1b0b2e;background:linear-gradient(135deg,#67e8f9,#e879f9);" +
    "box-shadow:0 0 10px rgba(232,121,249,.55);animation:battement 2.6s ease-in-out infinite}" +
    "@keyframes battement{0%,100%{opacity:1}50%{opacity:.62}}" +
    "@media (prefers-reduced-motion:reduce){.menu a.onglet-neuf .eti-neuf{animation:none}}" +
    "@media (max-width:900px){.menu a.onglet-neuf .eti-neuf{font-size:.52rem}}";

  function pastilleNeuve() {
    var a = document.querySelector('.menu a[href="dance.html"]');
    if (!a) return;

    if (!document.getElementById("style-neuf")) {
      var st = document.createElement("style");
      st.id = "style-neuf";
      st.textContent = STYLE_NEUF;
      document.head.appendChild(st);
    }

    a.classList.add("onglet-neuf");
    if (a.querySelector(".eti-neuf")) return;
    var e = document.createElement("span");
    e.className = "eti-neuf";
    e.textContent = "NEW";
    e.setAttribute("aria-hidden", "true");
    a.appendChild(e);
  }

  function pose() {
    var a = document.querySelector('a.rond[href="espace.html"], a.rond[href="connexion.html"]');
    if (!a) return;

    if (!document.getElementById("style-compte")) {
      var st = document.createElement("style");
      st.id = "style-compte";
      st.textContent = STYLE;
      document.head.appendChild(st);
    }

    var m = MOTS[langue()];
    var dedans = connecte();
    var mot = dedans ? m.espace : m.entrer;

    a.classList.add("rond--compte");
    a.setAttribute("href", dedans ? "espace.html" : "connexion.html");
    a.setAttribute("aria-label", mot);
    a.setAttribute("title", mot);

    var sp = a.querySelector(".mot-compte");
    if (!sp) {
      sp = document.createElement("span");
      sp.className = "mot-compte";
      a.appendChild(sp);
    }
    sp.textContent = mot;
    pastilleNeuve();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", pose);
  } else {
    pose();
  }

  /* la langue peut changer sans recharger la page */
  document.addEventListener("click", function (e) {
    if (e.target && e.target.closest && e.target.closest("#langue-liste")) {
      setTimeout(pose, 120);
    }
  });
})();
