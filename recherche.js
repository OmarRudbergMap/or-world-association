/* =====================================================================
   O.R. WORLD ASSOCIATION — LA RECHERCHE DU SITE
   ---------------------------------------------------------------------
   La loupe en haut de page ne faisait rien. Elle ouvre desormais une
   recherche : on tape un mot, on obtient les pages et les passages qui
   en parlent, dans la langue choisie.

   L'index est un petit fichier par langue, charge seulement au premier
   usage : une page qui n'est jamais cherchee ne telecharge rien.
   Accents et majuscules sont ignores, « adhesion » trouve « adhésion ».
   ===================================================================== */
(function () {
  "use strict";

  var MOTS = {
    fr: { titre: "Rechercher dans le site", invite: "Un mot, un nom, une question…",
          rien: "Rien trouvé pour", charge: "Un instant…",
          aide: "Tapez au moins deux lettres.", pages: "pages", page: "page",
          echec: "La recherche n'a pas pu se charger." },
    en: { titre: "Search the site", invite: "A word, a name, a question…",
          rien: "Nothing found for", charge: "One moment…",
          aide: "Type at least two letters.", pages: "pages", page: "page",
          echec: "The search could not be loaded." },
    es: { titre: "Buscar en el sitio", invite: "Una palabra, un nombre, una pregunta…",
          rien: "No se ha encontrado nada para", charge: "Un momento…",
          aide: "Escribe al menos dos letras.", pages: "páginas", page: "página",
          echec: "No se ha podido cargar la búsqueda." },
    sv: { titre: "Sök på webbplatsen", invite: "Ett ord, ett namn, en fråga…",
          rien: "Hittade inget för", charge: "Ett ögonblick…",
          aide: "Skriv minst två bokstäver.", pages: "sidor", page: "sida",
          echec: "Sökningen kunde inte laddas." },
    de: { titre: "Auf der Seite suchen", invite: "Ein Wort, ein Name, eine Frage…",
          rien: "Nichts gefunden für", charge: "Einen Moment…",
          aide: "Gib mindestens zwei Buchstaben ein.", pages: "Seiten", page: "Seite",
          echec: "Die Suche konnte nicht geladen werden." },
    pt: { titre: "Pesquisar no site", invite: "Uma palavra, um nome, uma pergunta…",
          rien: "Nada encontrado para", charge: "Um momento…",
          aide: "Escreva pelo menos duas letras.", pages: "páginas", page: "página",
          echec: "Não foi possível carregar a pesquisa." }
  };

  function langue() {
    var l = null;
    try { l = localStorage.getItem("orw-langue"); } catch (e) {}
    if (!l) l = window.ORW_LANGUE || (document.documentElement.lang || "fr").slice(0, 2);
    return MOTS[l] ? l : "fr";
  }
  function mot(cle) { return MOTS[langue()][cle]; }

  /* « Adhésion » et « adhesion » doivent se trouver l'un l'autre. */
  function plat(t) {
    t = String(t || "").toLowerCase();
    try { t = t.normalize("NFD").replace(/[̀-ͯ]/g, ""); } catch (e) {}
    return t;
  }
  function propre(t) {
    var d = document.createElement("div");
    d.textContent = t === null || t === undefined ? "" : String(t);
    return d.innerHTML;
  }
  function souligne(texte, mots) {
    var h = propre(texte), bas = plat(texte), sortie = "", pos = 0;
    var trouves = [];
    mots.forEach(function (m) {
      var i = bas.indexOf(m);
      while (i >= 0) { trouves.push([i, i + m.length]); i = bas.indexOf(m, i + m.length); }
    });
    if (!trouves.length) return h;
    trouves.sort(function (a, b) { return a[0] - b[0]; });
    var fusion = [];
    trouves.forEach(function (t) {
      if (fusion.length && t[0] <= fusion[fusion.length - 1][1]) {
        fusion[fusion.length - 1][1] = Math.max(fusion[fusion.length - 1][1], t[1]);
      } else fusion.push([t[0], t[1]]);
    });
    fusion.forEach(function (t) {
      sortie += propre(texte.slice(pos, t[0])) + "<mark>" + propre(texte.slice(t[0], t[1])) + "</mark>";
      pos = t[1];
    });
    return sortie + propre(texte.slice(pos));
  }

  var STYLE =
  ".rch-voile{position:fixed;inset:0;z-index:300;background:rgba(2,4,14,.82);" +
  "-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);display:flex;" +
  "align-items:flex-start;justify-content:center;padding:clamp(1rem,8vh,5rem) 1rem 2rem;overflow-y:auto}" +
  ".rch-voile[hidden]{display:none}" +
  ".rch-boite{width:min(680px,100%);border:1px solid #2a2550;border-radius:18px;overflow:hidden;" +
  "background:linear-gradient(158deg,rgba(28,18,66,.96),rgba(6,8,26,.99));box-shadow:0 30px 80px rgba(0,0,0,.6)}" +
  ".rch-haut{display:flex;align-items:center;gap:.7rem;padding:1rem 1.1rem;border-bottom:1px solid #2a2550}" +
  ".rch-haut svg{flex:none;opacity:.7}" +
  ".rch-champ{flex:1;background:none;border:0;outline:0;color:#e8eaf6;font-size:1.05rem;font-family:inherit;min-width:0}" +
  ".rch-champ::placeholder{color:#7b82a6}" +
  ".rch-champ::-webkit-search-cancel-button,.rch-champ::-webkit-search-decoration{-webkit-appearance:none;display:none}" +
  ".rch-x{flex:none;background:none;border:1px solid #2a2550;color:#9aa0bd;border-radius:999px;" +
  "width:30px;height:30px;cursor:pointer;font-size:1rem;line-height:1}" +
  ".rch-x:hover{color:#fff;border-color:#a78bfa}" +
  ".rch-corps{max-height:min(60vh,520px);overflow-y:auto;padding:.4rem 0 .6rem}" +
  ".rch-info{color:#9aa0bd;font-size:.86rem;padding:1.1rem 1.2rem;margin:0}" +
  ".rch-page{padding:.75rem 1.2rem .2rem;color:#67e8f9;font-size:.68rem;letter-spacing:.14em;text-transform:uppercase}" +
  ".rch-lien{display:block;padding:.55rem 1.2rem;color:#e8eaf6;text-decoration:none;border-left:2px solid transparent}" +
  ".rch-lien:hover,.rch-lien:focus{background:rgba(167,139,250,.12);border-left-color:#a78bfa;outline:0}" +
  ".rch-t{display:block;font-size:.95rem;margin-bottom:.15rem}" +
  ".rch-x2{display:block;color:#9aa0bd;font-size:.8rem;line-height:1.5}" +
  ".rch-lien mark{background:rgba(232,121,249,.28);color:#fff;border-radius:3px;padding:0 .1em}" +
  ".rch-pied{padding:.7rem 1.2rem;border-top:1px solid #2a2550;color:#7b82a6;font-size:.74rem}" +
  "@media (max-width:640px){.rch-voile{padding:0}.rch-boite{border-radius:0;min-height:100dvh;width:100%}" +
  ".rch-corps{max-height:none}}";

  var voile = null, champ = null, corps = null, pied = null, index = null, chargement = null;

  function construis() {
    var st = document.createElement("style");
    st.textContent = STYLE;
    document.head.appendChild(st);

    voile = document.createElement("div");
    voile.className = "rch-voile";
    voile.hidden = true;
    voile.setAttribute("role", "dialog");
    voile.setAttribute("aria-modal", "true");
    voile.innerHTML =
      '<div class="rch-boite">' +
        '<div class="rch-haut">' +
          '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">' +
            '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>' +
          '<input class="rch-champ" type="search" autocomplete="off" spellcheck="false">' +
          '<button class="rch-x" type="button" aria-label="Fermer">×</button>' +
        "</div>" +
        '<div class="rch-corps"></div>' +
        '<p class="rch-pied"></p>' +
      "</div>";
    document.body.appendChild(voile);

    champ = voile.querySelector(".rch-champ");
    corps = voile.querySelector(".rch-corps");
    pied  = voile.querySelector(".rch-pied");

    voile.querySelector(".rch-x").addEventListener("click", ferme);
    voile.addEventListener("click", function (e) { if (e.target === voile) ferme(); });
    champ.addEventListener("input", function () { cherche(champ.value); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !voile.hidden) ferme();
    });
  }

  function charge() {
    if (index) return Promise.resolve(index);
    if (chargement) return chargement;
    chargement = fetch("recherche-" + langue() + ".json", { cache: "force-cache" })
      .then(function (r) { if (!r.ok) throw new Error("absent"); return r.json(); })
      .then(function (j) { index = j; return j; });
    return chargement;
  }

  function cherche(q) {
    var mots = plat(q).split(/\s+/).filter(function (m) { return m.length >= 2; });
    if (!mots.length) {
      corps.innerHTML = '<p class="rch-info">' + propre(mot("aide")) + "</p>";
      pied.textContent = "";
      return;
    }
    if (!index) {
      corps.innerHTML = '<p class="rch-info">' + propre(mot("charge")) + "</p>";
      charge().then(function () { cherche(champ.value); })
              .catch(function () { corps.innerHTML = '<p class="rch-info">' + propre(mot("echec")) + "</p>"; });
      return;
    }

    /* « don » ne doit pas remonter « donnees » : un mot court n'est
       accepte qu'en debut de mot. Les mots longs restent tolerants,
       pour que « adhesio » trouve encore « adhesion ». */
    function trouve(foin, m) {
      var i = foin.indexOf(m);
      while (i >= 0) {
        var avant = i === 0 ? " " : foin.charAt(i - 1);
        var debutDeMot = !/[a-z0-9]/.test(avant);
        if (debutDeMot) return 2;          // au commencement d'un mot
        if (m.length >= 4) return 1;       // au milieu, seulement si le mot est long
        i = foin.indexOf(m, i + 1);
      }
      return 0;
    }

    var resultats = [];
    index.forEach(function (pg) {
      var dedans = [];
      pg.s.forEach(function (sec) {
        var dansT = plat(sec.t), dansX = plat(sec.x || "");
        var score = 0;
        for (var i = 0; i < mots.length; i++) {
          var a = trouve(dansT, mots[i]), b = trouve(dansX, mots[i]);
          if (!a && !b) return;
          score += a * 3 + b;
        }
        dedans.push({ sec: sec, score: score });
      });
      var titre = plat(pg.t);
      var dansTitre = mots.every(function (m) { return trouve(titre, m) > 0; });
      /* Le nom du fichier est le signal le plus sur : qui tape
         « adhesion » veut adhesion.html, meme si le grand titre de la
         page dit « Adherer a l'association ». */
      var nom = plat(String(pg.p).replace(/\.html$/, "").replace(/[-_]/g, " "));
      var dansNom = mots.every(function (m) { return trouve(nom, m) > 0; });
      if (dedans.length || dansTitre || dansNom) {
        dedans.sort(function (a, b) { return b.score - a.score; });
        /* La page qui porte le mot dans son titre passe devant : qui
           cherche « Young Royals » veut la page Young Royals, pas la
           page Presse qui en parle vingt fois. On ne compte ensuite que
           les quatre meilleurs passages, pour qu'une page bavarde ne
           prenne pas la premiere place a force de repetitions. */
        resultats.push({ pg: pg, bouts: dedans.slice(0, 4),
          score: (dansNom ? 80 : 0) + (dansTitre ? 40 : 0) +
                 dedans.slice(0, 4).reduce(function (a, x) { return a + x.score; }, 0) });
      }
    });
    resultats.sort(function (a, b) { return b.score - a.score; });

    if (!resultats.length) {
      corps.innerHTML = '<p class="rch-info">' + propre(mot("rien")) + " « " + propre(q.trim()) + " ».</p>";
      pied.textContent = "";
      return;
    }

    var h = "";
    resultats.slice(0, 12).forEach(function (r) {
      h += '<p class="rch-page">' + propre(r.pg.t) + "</p>";
      if (!r.bouts.length) {
        h += '<a class="rch-lien" href="' + propre(r.pg.p) + '"><span class="rch-t">' +
             souligne(r.pg.t, mots) + "</span></a>";
      }
      r.bouts.forEach(function (b) {
        var cible = r.pg.p;
        try { cible += "#:~:text=" + encodeURIComponent(b.sec.t.slice(0, 60)); } catch (e) {}
        h += '<a class="rch-lien" href="' + propre(cible) + '">' +
             '<span class="rch-t">' + souligne(b.sec.t, mots) + "</span>" +
             (b.sec.x ? '<span class="rch-x2">' + souligne(b.sec.x, mots) + "</span>" : "") +
             "</a>";
      });
    });
    corps.innerHTML = h;
    pied.textContent = resultats.length + " " + (resultats.length > 1 ? mot("pages") : mot("page"));
  }

  function ouvre() {
    if (!voile) construis();
    voile.hidden = false;
    champ.placeholder = mot("invite");
    voile.setAttribute("aria-label", mot("titre"));
    document.body.style.overflow = "hidden";
    charge().catch(function () {});
    setTimeout(function () { champ.focus(); }, 40);
    cherche(champ.value);
  }
  function ferme() {
    if (!voile) return;
    voile.hidden = true;
    document.body.style.overflow = "";
  }

  function pose() {
    var l = document.querySelectorAll('button.rond[aria-label], button.rond');
    for (var i = 0; i < l.length; i++) {
      var b = l[i];
      if (b.closest("a")) continue;
      if (b.dataset.rchPose) continue;
      b.dataset.rchPose = "1";
      b.addEventListener("click", function (e) { e.preventDefault(); e.stopPropagation(); ouvre(); });
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", pose);
  else pose();

  window.ORW_RECHERCHE = ouvre;
})();
