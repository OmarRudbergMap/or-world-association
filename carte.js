/* =====================================================================
   O.R. WORLD ASSOCIATION — LA CARTE DES VISITES
   ---------------------------------------------------------------------
   Le monde deplie a plat, dessine avec les memes littoraux que le globe
   de la page « Omar infos ». Un point lumineux par pays, dont la taille
   et l'eclat suivent le nombre de visites. Les plus gros respirent
   doucement, comme les etoiles du globe.
   ===================================================================== */
(function () {
  "use strict";

  var LAT_HAUT = 78, LAT_BAS = -58;   // on coupe les poles, vides et deformants
  var COUL = ["103,232,249", "167,139,250", "232,121,249"];

  window.ORW_CARTE = function (toile, pays, auSurvol, reglages) {
    reglages = reglages || {};
    var ETOILE = reglages.forme === "etoile";
    var x = toile.getContext("2d");
    var L = 0, H = 0, dpr = 1, points = [], max = 1, anim = null, survol = -1;
    /* Le rectangle ou la carte est reellement dessinee. Il garde
       toujours les memes proportions : 360 degres de longitude pour
       136 de latitude. Le reste de la toile demeure en ciel de nuit.
       Sans cela, un ecran etroit ecrase les continents. */
    var MX = 0, MY = 0, ML = 0, MH = 0, ech = 1;
    var RATIO = 360 / (LAT_HAUT - LAT_BAS);

    function cadre() {
      if (L / H > RATIO) { MH = H; ML = H * RATIO; }
      else { ML = L; MH = L / RATIO; }
      MX = (L - ML) / 2;
      MY = (H - MH) / 2;
      /* Sur un petit ecran, des astres a la taille du grand ecran
         mangeraient la carte : ils retrecissent avec elle. */
      ech = Math.max(.55, Math.min(1, ML / 820));
    }


    function projette(la, lo) {
      return [
        MX + (lo + 180) / 360 * ML,
        MY + (LAT_HAUT - la) / (LAT_HAUT - LAT_BAS) * MH
      ];
    }

    function dim() {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      L = toile.clientWidth;
      H = toile.clientHeight;
      toile.width = L * dpr;
      toile.height = H * dpr;
      x.setTransform(dpr, 0, 0, dpr, 0, 0);
      cadre();
      trace = null;
      place();
    }

    function place() {
      points = [];
      max = 1;
      for (var i = 0; i < pays.length; i++) if (pays[i].vues > max) max = pays[i].vues;
      for (var k = 0; k < pays.length; k++) {
        var c = window.ORW_CENTRES[pays[k].pays];
        if (!c) continue;
        var p = projette(c[0], c[1]);
        if (p[1] < -20 || p[1] > H + 20) continue;
        points.push({
          code: pays[k].pays,
          vues: pays[k].vues,
          x: p[0], y: p[1],
          r: ((ETOILE ? 5.2 : 2.6) + (ETOILE ? 9 : 13) * Math.sqrt(pays[k].vues / max)) * ech,
          c: COUL[k % COUL.length],
          ph: (k * 1.7) % 6.28
        });
      }
      /* les gros points en dessous, pour que les petits restent cliquables */
      points.sort(function (a, b) { return b.r - a.r; });
    }

    function cotes() {
      var p = new Path2D();
      for (var k = 0; k < window.ORW_COTES.length; k++) {
        var tr = window.ORW_COTES[k], pose = false;
        for (var i = 0; i < tr.length; i++) {
          var lo = tr[i][0], la = tr[i][1];
          if (la > LAT_HAUT || la < LAT_BAS) { pose = false; continue; }
          var q = projette(la, lo);
          if (pose) p.lineTo(q[0], q[1]); else p.moveTo(q[0], q[1]);
          pose = true;
        }
      }
      return p;
    }

    var trace = null;

    /* une etoile a cinq branches, le meme trace que celles du globe */
    function etoile(cx, cy, r, tour) {
      x.beginPath();
      for (var i = 0; i < 10; i++) {
        var a = -Math.PI / 2 + i * Math.PI / 5 + tour;
        var rr = (i % 2) ? r * .42 : r;
        var px = cx + Math.cos(a) * rr, py = cy + Math.sin(a) * rr;
        if (i) x.lineTo(px, py); else x.moveTo(px, py);
      }
      x.closePath();
    }


    function dessine(t) {
      x.clearRect(0, 0, L, H);

      /* le fond : une nuit legerement bleutee */
      var f = x.createLinearGradient(0, 0, 0, H);
      f.addColorStop(0, "rgba(14,18,48,.85)");
      f.addColorStop(1, "rgba(6,8,26,.95)");
      x.fillStyle = f;
      x.fillRect(0, 0, L, H);

      /* les littoraux, deux passages comme sur le globe */
      if (!trace) trace = cotes();
      x.save();
      x.globalCompositeOperation = "lighter";
      x.strokeStyle = "rgba(120,205,255,.26)";
      x.lineWidth = 2;
      x.stroke(trace);
      x.strokeStyle = "rgba(225,248,255,.5)";
      x.lineWidth = .7;
      x.stroke(trace);
      x.restore();

      /* les points */
      x.save();
      x.globalCompositeOperation = "lighter";
      for (var i = 0; i < points.length; i++) {
        var p = points[i];
        var bat = .78 + .22 * Math.sin(t * .0016 + p.ph);
        var r = p.r * (survol === i ? 1.22 : 1);

        var g = x.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 3.1);
        g.addColorStop(0, "rgba(" + p.c + "," + (.55 * bat).toFixed(3) + ")");
        g.addColorStop(1, "rgba(" + p.c + ",0)");
        x.fillStyle = g;
        x.beginPath(); x.arc(p.x, p.y, r * 3.1, 0, 6.3); x.fill();

        if (ETOILE) {
          x.fillStyle = "rgba(" + p.c + "," + (.95 * bat).toFixed(3) + ")";
          etoile(p.x, p.y, r, p.ph * .04);
          x.fill();
          x.fillStyle = "rgba(255,255,255," + (.75 * bat).toFixed(3) + ")";
          etoile(p.x, p.y, r * .46, p.ph * .04);
          x.fill();
        } else {
          x.fillStyle = "rgba(" + p.c + "," + (.9 * bat).toFixed(3) + ")";
          x.beginPath(); x.arc(p.x, p.y, r, 0, 6.3); x.fill();

          x.fillStyle = "rgba(255,255,255," + (.85 * bat).toFixed(3) + ")";
          x.beginPath(); x.arc(p.x, p.y, Math.max(1, r * .32), 0, 6.3); x.fill();
        }
      }
      x.restore();

      anim = requestAnimationFrame(dessine);
    }

    function vise(ev) {
      var b = toile.getBoundingClientRect();
      var mx = ev.clientX - b.left, my = ev.clientY - b.top;
      var trouve = -1, mieux = 1e9;
      for (var i = points.length - 1; i >= 0; i--) {
        var d = Math.hypot(points[i].x - mx, points[i].y - my);
        if (d < Math.max(points[i].r, 9) && d < mieux) { mieux = d; trouve = i; }
      }
      if (trouve !== survol) {
        survol = trouve;
        toile.style.cursor = trouve >= 0 ? "pointer" : "default";
        if (auSurvol) auSurvol(trouve >= 0 ? points[trouve] : null, mx, my);
      }
    }

    toile.addEventListener("mousemove", vise);
    /* Sur telephone il n'y a pas de survol : une tape montre l'infobulle. */
    toile.addEventListener("click", vise);
    toile.addEventListener("mouseleave", function () {
      survol = -1;
      toile.style.cursor = "default";
      if (auSurvol) auSurvol(null, 0, 0);
    });

    window.addEventListener("resize", function () { trace = null; dim(); });

    dim();
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      dessine(0);
      cancelAnimationFrame(anim);
      anim = null;
    } else {
      anim = requestAnimationFrame(dessine);
    }

    return { redessine: function (nouveaux) { pays = nouveaux; place(); } };
  };
})();
