/* Tarjeta digital de SHELBY CAPS: página pública única con redes, catálogo,
 * envíos, formas de pago, promociones y la tarjeta de lealtad. El contenido
 * lo captura el dueño desde el POS (Admin → Tarjeta digital) y se publica en
 * la tabla `business_card` de Supabase — aquí solo se lee y se pinta, sin
 * carrito ni checkout.
 *
 * Los banners que rotan arriba **no son propios de esta página**: son los
 * mismos que ya se administran en Admin → Anuncios de la tienda y que rotan
 * en la portada del catálogo (misma tabla `catalog_banners`, mismo carrusel).
 */
(function () {
  "use strict";
  const CFG = window.CATALOGO_CONFIG;
  const HEADERS = {
    apikey: CFG.SUPABASE_ANON,
    Authorization: "Bearer " + CFG.SUPABASE_ANON,
  };
  const $ = (id) => document.getElementById(id);

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, (m) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));
  }

  async function rest(path) {
    const res = await fetch(CFG.SUPABASE_URL + "/rest/v1/" + path, { headers: HEADERS });
    if (!res.ok) throw new Error("HTTP " + res.status);
    return res.json();
  }

  function toast(msg) {
    const t = document.createElement("div");
    t.className = "toast";
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 1800);
  }

  function renderShopBar() {
    $("shopName").textContent = CFG.SHOP_NAME || "Tarjeta digital";
    $("footName").textContent = CFG.SHOP_NAME || "";
    document.title = (CFG.SHOP_NAME || "Catálogo") + " | Tarjeta digital";
  }

  // ---- Banners (idéntico al carrusel del catálogo: misma tabla, mismo
  // comportamiento — se detiene en cuanto el usuario lo toca). ----
  let BANNER_LIST = [];
  function applyPublishedBanners(rows) {
    if (!rows || !rows.length) return;
    BANNER_LIST = rows
      .filter((r) => !r.is_cover)
      .sort((a, b) => a.position - b.position)
      .map((r) => ({ image: r.url, alt: r.caption || "", link: r.link || null }));
  }

  function renderBanners() {
    const list = BANNER_LIST;
    if (!list.length) return;
    const box = $("banners");
    const track = $("btrack");
    const dots = $("bdots");

    track.innerHTML = list.map((b, i) => {
      const img = '<img src="' + esc(b.image) + '" alt="' + esc(b.alt || "") +
        '"' + (i === 0 ? "" : ' loading="lazy"') + " />";
      return b.link
        ? '<a href="' + esc(b.link) + '" target="_blank" rel="noopener">' + img + "</a>"
        : "<span>" + img + "</span>";
    }).join("");
    dots.innerHTML = list.length > 1
      ? list.map((_, i) => '<span class="dot' + (i === 0 ? " on" : "") + '"></span>').join("")
      : "";
    box.hidden = false;
    if (list.length < 2) return;

    const paint = (i) => dots.querySelectorAll(".dot")
      .forEach((d, k) => d.classList.toggle("on", k === i));
    let timer = null;
    const step = () => {
      const i = Math.round(track.scrollLeft / track.clientWidth);
      const next = (i + 1) % list.length;
      track.scrollTo({ left: next * track.clientWidth, behavior: "smooth" });
    };
    const start = () => {
      stop();
      timer = setInterval(step, Math.max(2, CFG.BANNER_SECONDS || 5) * 1000);
    };
    const stop = () => { if (timer) { clearInterval(timer); timer = null; } };

    track.onscroll = () => paint(Math.round(track.scrollLeft / track.clientWidth));
    ["pointerdown", "touchstart", "wheel"].forEach((ev) =>
      track.addEventListener(ev, stop, { passive: true }));
    document.addEventListener("visibilitychange", () =>
      document.hidden ? stop() : (timer && start()));
    start();
  }

  // ---- Ligas de redes: acepta @usuario, un dominio suelto o la liga completa
  // — lo que sea que haya capturado el dueño en el POS, sin pedirle un
  // formato exacto. ----
  function toUrl(value, prefixIfHandle) {
    const v = (value || "").trim();
    if (!v) return "";
    if (/^https?:\/\//i.test(v)) return v;
    if (v.startsWith("@")) return prefixIfHandle + v.slice(1);
    if (v.includes(".")) return "https://" + v.replace(/^\/+/, "");
    return prefixIfHandle + v;
  }
  function waUrl(digits) {
    const d = (digits || "").replace(/\D/g, "");
    return d ? "https://wa.me/" + d : "";
  }
  function mapsUrl(value) {
    const v = (value || "").trim();
    if (!v) return "";
    if (/^https?:\/\//i.test(v)) return v;
    return "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(v);
  }

  // ---- Íconos (línea simple, mismo lenguaje visual que el resto del sitio;
  // no son los logotipos oficiales de cada red). ----
  const ICONS = {
    whatsapp: '<svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-3.2-6.4"/><path d="M8.5 9.5c0 4 2 6 6 6l1.5-1.5-2-1.5-1 1c-1-.5-1.8-1.3-2.3-2.3l1-1L10 8 8.5 9.5Z"/></svg>',
    tiktok: '<svg viewBox="0 0 24 24"><path d="M15 4v9.7a3.4 3.4 0 1 1-3-3.37"/><path d="M15 4c.35 2.3 1.9 4 4 4.3"/></svg>',
    facebook: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M13.8 8.2h-1.2c-.9 0-1.4.5-1.4 1.4V11H9v2h2.2v5h2V13H15l.3-2h-2.1V9.9c0-.4.2-.6.6-.6h1.6z"/></svg>',
    instagram: '<svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.3" cy="6.7" r="1" fill="currentColor" stroke="none"/></svg>',
    location: '<svg viewBox="0 0 24 24"><path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/></svg>',
    cart: '<svg viewBox="0 0 24 24"><path d="M3 4h2l2.6 11h10L20 7H6"/><circle cx="9.5" cy="19" r="1.6"/><circle cx="17" cy="19" r="1.6"/></svg>',
    tag: '<svg viewBox="0 0 24 24"><path d="M12.6 3.5 20 10.9a2 2 0 0 1 0 2.8l-6.3 6.3a2 2 0 0 1-2.8 0L3.5 12.6V4a.5.5 0 0 1 .5-.5h8.6Z"/><circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none"/></svg>',
    copy: '<svg viewBox="0 0 24 24"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
    check: '<svg viewBox="0 0 24 24"><path d="m5 13 4 4L19 7"/></svg>',
    chev: '<svg class="chev" viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></svg>',
  };

  function section(title, inner) {
    return '<section class="card-section"><h2>' + esc(title) + '</h2>' + inner + '</section>';
  }

  function renderSocials(s) {
    if (!s) return "";
    const rows = [];
    const link = (icon, label, href) => href
      ? '<a class="link-row" href="' + esc(href) + '" target="_blank" rel="noopener">' +
        ICONS[icon] + "<span>" + esc(label) + "</span>" + ICONS.chev + "</a>"
      : "";
    if (s.whatsapp) rows.push(link("whatsapp", "WhatsApp", waUrl(s.whatsapp)));
    if (s.tiktok) rows.push(link("tiktok", "TikTok", toUrl(s.tiktok, "https://www.tiktok.com/@")));
    if (s.facebook) rows.push(link("facebook", "Facebook", toUrl(s.facebook, "https://facebook.com/")));
    if (s.instagram) rows.push(link("instagram", "Instagram", toUrl(s.instagram, "https://instagram.com/")));
    if (s.locationUrl) rows.push(link("location", "Ubicación", mapsUrl(s.locationUrl)));
    const filled = rows.filter(Boolean);
    if (!filled.length) return "";
    return section("Síguenos y contáctanos", '<div class="link-list">' + filled.join("") + "</div>");
  }

  function renderCatalog(url) {
    const href = (url || "").trim();
    if (!href) return "";
    return section("Catálogo de gorras",
      '<a class="catalog-btn" href="' + esc(href) + '">' + ICONS.cart +
      "<span>Ver catálogo</span></a>");
  }

  function renderShipping(notice, faq) {
    const items = Array.isArray(faq) ? faq.filter((f) => f && f.q && f.a) : [];
    if (!notice && !items.length) return "";
    const noticeHtml = notice ? '<p class="shipnotice">' + esc(notice) + "</p>" : "";
    const faqHtml = items.map((f) =>
      '<div class="faq-item"><p class="faq-q">' + esc(f.q) + '</p>' +
      '<p class="faq-a">' + esc(f.a) + "</p></div>").join("");
    return section("Dudas sobre envíos", noticeHtml + faqHtml);
  }

  function renderSteps(steps) {
    const list = Array.isArray(steps) ? steps.filter(Boolean) : [];
    if (!list.length) return "";
    const rows = list.map((s, i) =>
      '<div class="step-row"><span class="step-n">' + (i + 1) + '</span>' +
      '<p>' + esc(s) + "</p></div>").join("");
    return section("Proceso de compra", '<div class="step-list">' + rows + "</div>");
  }

  function payField(label, value) {
    if (!value) return "";
    const id = "cp" + Math.random().toString(36).slice(2, 8);
    return '<div class="pay-field"><div class="pf-text"><p class="pf-label">' + esc(label) +
      '</p><p class="pf-value">' + esc(value) + '</p></div>' +
      '<button class="copy-btn" type="button" data-copy="' + esc(value) + '" id="' + id + '" ' +
      'aria-label="Copiar ' + esc(label) + '">' + ICONS.copy + "</button></div>";
  }

  function renderPayments(bank, oxxo) {
    const bankFields = bank
      ? payField("Banco", bank.bank) + payField("CLABE", bank.clabe) +
        payField("Número de cuenta", bank.accountNumber) + payField("Titular", bank.holder)
      : "";
    const oxxoFields = oxxo
      ? payField("Banco", oxxo.bank) + payField("Número de tarjeta", oxxo.cardNumber)
      : "";
    if (!bankFields && !oxxoFields) return "";
    let inner = "";
    if (bankFields) inner += '<p class="pf-label" style="margin:0 0 6px">Transferencia bancaria</p><div class="pay-box">' + bankFields + "</div>";
    if (oxxoFields) inner += '<p class="pf-label" style="margin:0 0 6px">Depósito en OXXO / 7-Eleven</p><div class="pay-box">' + oxxoFields + "</div>";
    return section("Formas de pago", inner);
  }

  function renderPromotions(list) {
    const items = Array.isArray(list) ? list.filter(Boolean) : [];
    if (!items.length) return "";
    const rows = items.map((p) =>
      '<div class="promo-row">' + ICONS.tag + "<span>" + esc(p) + "</span></div>").join("");
    return section("Paquetes y promociones", '<div class="promo-list">' + rows + "</div>");
  }

  function renderLoyalty(text, image) {
    if (!text && !image) return "";
    const img = image ? '<img class="loyalty-photo" src="' + esc(image) + '" alt="Tarjeta de lealtad" />' : "";
    const p = text ? '<p class="loyalty-text">' + esc(text) + "</p>" : "";
    return section("Tarjeta de lealtad", img + p);
  }

  function wireCopyButtons(root) {
    root.querySelectorAll(".copy-btn").forEach((btn) => {
      btn.onclick = async () => {
        const value = btn.getAttribute("data-copy") || "";
        try {
          await navigator.clipboard.writeText(value);
          btn.classList.add("done");
          btn.innerHTML = ICONS.check;
          toast("Copiado");
          setTimeout(() => {
            btn.classList.remove("done");
            btn.innerHTML = ICONS.copy;
          }, 1500);
        } catch (_) {
          toast("No se pudo copiar");
        }
      };
    });
  }

  function render(data) {
    const html = [
      renderSocials(data.socials),
      renderCatalog(data.catalogUrl),
      renderShipping(data.shippingNotice, data.shippingFaq),
      renderSteps(data.purchaseSteps),
      renderPayments(data.bankTransfer, data.oxxoDeposit),
      renderPromotions(data.promotions),
      renderLoyalty(data.loyaltyText, data.loyaltyImagePath),
    ].filter(Boolean).join("");

    const main = $("main");
    if (!html) {
      main.innerHTML = '<p class="state">Esta tarjeta todavía no tiene contenido.</p>';
      return;
    }
    main.innerHTML = html;
    wireCopyButtons(main);
  }

  async function init() {
    renderShopBar();

    try {
      applyPublishedBanners(await rest("catalog_banners?select=*&order=position.asc"));
    } catch (_) {
      // Sin anuncios publicados: la tarjeta simplemente no muestra el carrusel.
    }
    renderBanners();

    try {
      const rows = await rest("business_card?select=data&id=eq.1");
      const data = rows && rows[0] ? rows[0].data : null;
      if (!data) {
        $("state").textContent = "Esta tarjeta todavía no se ha publicado.";
        return;
      }
      render(data);
    } catch (e) {
      $("state").textContent = "No se pudo cargar la tarjeta: " + e.message;
    }
  }

  init();
})();
