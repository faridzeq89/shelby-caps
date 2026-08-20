/* Tienda web de SHELBY CAPS (solo lectura del catálogo publicado por el POS).
 *
 * El carrito replica la lógica de mayoreo del POS: el precio baja al alcanzar
 * el escalón contando la cantidad **surtida entre variantes del mismo
 * producto**, no por variante suelta.
 *
 * El cobro (Mercado Pago) se enchufa en la fase #8: "Continuar al pago" es
 * todavía un marcador. */
(function () {
  "use strict";
  const CFG = window.CATALOGO_CONFIG;
  const HEADERS = {
    apikey: CFG.SUPABASE_ANON,
    Authorization: "Bearer " + CFG.SUPABASE_ANON,
  };

  // ---- Estado ----
  let PRODUCTS = [];
  let VARIANTS = new Map(); // productId -> [variant]
  let TIERS = new Map(); // productId -> [tier]
  let IMAGES = new Map(); // productId -> [url] (posición 0 = principal)
  let CATEGORIES = []; // [{name, position, active}] tal como las publicó el POS
  let categoryFilter = null; // null = todas
  let query = "";
  let sortBy = "none";
  let listView = false;
  let current = null; // producto abierto en la ficha
  let currentVariant = null;
  const cart = new Map(); // variantId -> { qty, variant, product }

  const $ = (id) => document.getElementById(id);

  /** Precio con separador de miles, como el catálogo original ($1,300). */
  function money(cents) {
    const v = Math.round(cents) / 100;
    const s = v.toFixed(v % 1 === 0 ? 0 : 2);
    const [int, dec] = s.split(".");
    return "$" + int.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (dec ? "." + dec : "");
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, (m) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));
  }

  async function rest(path) {
    const res = await fetch(CFG.SUPABASE_URL + "/rest/v1/" + path, { headers: HEADERS });
    if (!res.ok) throw new Error("HTTP " + res.status);
    return res.json();
  }

  // ---- Reglas de precio (espejo del POS) ----
  function wholesalePriceFor(tiers, qty) {
    let best = null, bestMin = -1;
    for (const t of tiers || []) {
      if (qty >= t.min_qty && t.min_qty > bestMin) { bestMin = t.min_qty; best = t.price_cents; }
    }
    return best;
  }

  function variantsOf(id) { return VARIANTS.get(id) || []; }
  function imagesOf(id) { return IMAGES.get(id) || []; }
  function stockOf(id) { return variantsOf(id).reduce((s, v) => s + (v.stock || 0), 0); }

  /** Precio de lista del producto: el menor de sus variantes. */
  function priceOf(id) {
    const vs = variantsOf(id);
    return vs.length ? Math.min(...vs.map((v) => v.price_cents)) : null;
  }

  function aggregateByProduct() {
    const m = new Map();
    for (const { qty, product } of cart.values()) {
      m.set(product.id, (m.get(product.id) || 0) + qty);
    }
    return m;
  }

  function pricedCart() {
    const agg = aggregateByProduct();
    const lines = [];
    for (const entry of cart.values()) {
      const w = wholesalePriceFor(TIERS.get(entry.product.id), agg.get(entry.product.id) || 0);
      const unit = w != null ? w : entry.variant.price_cents;
      lines.push({ ...entry, unit, wholesale: w != null, lineTotal: unit * entry.qty });
    }
    return lines;
  }

  const cartCount = () => [...cart.values()].reduce((n, e) => n + e.qty, 0);
  const cartTotal = () => pricedCart().reduce((s, l) => s + l.lineTotal, 0);

  function addToCart(product, variant, delta) {
    const cur = cart.get(variant.id);
    const qty = Math.min((cur ? cur.qty : 0) + delta, variant.stock || 0);
    if (qty <= 0) cart.delete(variant.id);
    else cart.set(variant.id, { qty, variant, product });
    renderCartCount();
  }

  function toast(msg) {
    const t = document.createElement("div");
    t.className = "toast";
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 1800);
  }

  // ---- Horario de la tienda ----
  /** Marca abierto/cerrado según `OPENING_HOURS` de config.js. */
  function renderShopBar() {
    $("shopName").textContent = CFG.SHOP_NAME || "Catálogo";
    $("footName").textContent = CFG.SHOP_NAME || "";
    document.title = (CFG.SHOP_NAME || "Catálogo") + " | Catálogo Online";
    if (CFG.ADDRESS) $("address").textContent = CFG.ADDRESS;
    else $("address").hidden = true;

    const hours = CFG.OPENING_HOURS;
    if (!hours) { $("shopbar").hidden = true; return; }
    const now = new Date();
    const today = hours[now.getDay()]; // 0 = domingo
    const mins = now.getHours() * 60 + now.getMinutes();
    const toMin = (hhmm) => {
      const [h, m] = hhmm.split(":").map(Number);
      return h * 60 + m;
    };
    const open = !!today && mins >= toMin(today[0]) && mins < toMin(today[1]);
    const fmt = (hhmm) => {
      const [h, m] = hhmm.split(":").map(Number);
      const ap = h >= 12 ? "p. m." : "a. m.";
      const h12 = h % 12 === 0 ? 12 : h % 12;
      return h12 + ":" + String(m).padStart(2, "0") + " " + ap;
    };
    const dias = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
    let text;
    if (open) {
      text = "Abierto hoy, " + fmt(today[0]) + " - " + fmt(today[1]);
    } else {
      // Busca el próximo día con horario para decir cuándo abre.
      let d = now.getDay(), next = null;
      for (let i = 0; i < 8; i++) {
        const cand = hours[(d + i) % 7];
        if (cand && !(i === 0 && mins >= toMin(cand[1]))) { next = [(d + i) % 7, cand]; break; }
      }
      text = next
        ? "Abre " + dias[next[0]] + ", " + fmt(next[1][0]) + " - " + fmt(next[1][1])
        : "Sin horario";
    }
    $("hoursText").textContent = text;
    const badge = $("openBadge");
    badge.textContent = open ? "Abierto" : "Cerrado";
    badge.classList.toggle("open", open);
  }

  // ---- Envíos y compra ----
  /// Preguntas frecuentes. **Fuente:** primero la tarjeta digital publicada
  /// desde el POS (Admin → Tarjeta digital, tabla `business_card` — editable
  /// sin tocar código); si no hay nada publicado ahí, cae a `config.js`. Es
  /// el mismo patrón de resguardo que ya usan los banners: nunca se ve a
  /// medias, y el dueño deja de necesitar ayuda para cambiar un tiempo de
  /// entrega.
  ///
  /// Los dos enlaces que abren esta hoja (pie de página y pantalla de "Datos
  /// de contacto") arrancan ocultos en el HTML y solo se muestran si hay algo
  /// que contar, para que vaciar la FAQ no deje un botón que abre una hoja en
  /// blanco.
  function renderShipping(cardData) {
    const fromCard = cardData && Array.isArray(cardData.shippingFaq) &&
      cardData.shippingFaq.length
      ? { NOTICE: cardData.shippingNotice, FAQ: cardData.shippingFaq }
      : null;
    const info = fromCard || CFG.SHIPPING;
    const faq = info && info.FAQ ? info.FAQ : [];
    if (!faq.length) return; // los enlaces se quedan `hidden` como en el HTML

    const notice = info.NOTICE
      ? `<p class="shipnotice">${esc(info.NOTICE)}</p>`
      : "";
    const items = faq.map((it) =>
      `<div class="faq-item"><p class="faq-q">${esc(it.q)}</p>` +
      `<p class="faq-a">${esc(it.a)}</p></div>`
    ).join("");
    $("shipBody").innerHTML = notice + items;

    $("footShipping").hidden = false;
    $("coShipping").hidden = false;
  }

  function openShipping() {
    $("shippingSheet").hidden = false;
    document.body.style.overflow = "hidden";
  }
  function closeShipping() {
    $("shippingSheet").hidden = true;
    // Se puede abrir ENCIMA de "Datos de contacto" (esa hoja sigue ahí
    // debajo, con su propio bloqueo de scroll); solo se libera si de verdad
    // no queda ninguna otra hoja abierta.
    if ($("checkoutSheet").hidden) document.body.style.overflow = "";
  }

  // ---- Portada y banners ----
  /// Los anuncios los administra el dueño desde el POS. Mientras no suba
  /// ninguno, se muestran los de ejemplo de `config.js`, para que la tienda
  /// nunca se vea a medias.
  let COVER_SRC = CFG.COVER;
  let BANNER_LIST = CFG.BANNERS || [];

  function applyPublishedBanners(rows) {
    if (!rows || !rows.length) return;
    const cover = rows.find((r) => r.is_cover);
    const rest = rows.filter((r) => !r.is_cover)
      .sort((a, b) => a.position - b.position);
    if (cover) COVER_SRC = cover.url;
    if (rest.length) {
      BANNER_LIST = rest.map((r) => ({
        image: r.url,
        alt: r.caption || "",
        link: r.link || null,
      }));
    }
  }

  function renderCover() {
    const src = COVER_SRC;
    if (!src) return;
    const el = $("cover");
    el.innerHTML = '<img src="' + esc(src) + '" alt="' +
      esc(CFG.SHOP_NAME || "") + '" />';
    el.hidden = false;
  }

  /// Banners que rotan solos. Se detienen en cuanto el usuario los toca: nada
  /// más molesto que un carrusel que se mueve mientras lo estás viendo.
  function renderBanners() {
    const list = BANNER_LIST;
    if (!list.length) return;
    const box = $("banners");
    const track = $("btrack");
    const dots = $("bdots");

    track.innerHTML = list.map((b, i) => {
      // El primero se carga de inmediato (es lo primero que se ve); los demás
      // pueden esperar a que el usuario deslice.
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
    // Si el usuario interactúa, se detiene y ya no vuelve a arrancar solo.
    ["pointerdown", "touchstart", "wheel"].forEach((ev) =>
      track.addEventListener(ev, stop, { passive: true }));
    // Tampoco corre si la pestaña está en segundo plano.
    document.addEventListener("visibilitychange", () =>
      document.hidden ? stop() : (timer && start()));
    start();
  }

  // ---- Categorías ----
  /* El orden y las archivadas los decide el POS (tabla `catalog_categories`,
   * SQL 0007). Reglas:
   *
   *  - Con lista publicada: manda ella. Sale la categoría que esté ACTIVA y que
   *    además tenga productos a la venta; en el orden que el dueño acomodó, no
   *    alfabético. Una categoría archivada no sale ni con productos colgando.
   *  - Sin lista (proyecto sin el SQL 0007, o publicado por un POS viejo): se
   *    deducen de los productos y se acomodan por nombre, como antes.
   *  - Una categoría que viene en los productos pero no en la lista (publicada
   *    por una versión anterior) se agrega al final, alfabética: es mejor que
   *    esconder mercancía. */
  function orderedCategories() {
    const enUso = new Set(PRODUCTS.map((p) => p.category).filter(Boolean));
    if (!CATEGORIES.length) return [...enUso].sort();
    const conocidas = new Set(CATEGORIES.map((c) => c.name));
    const orden = CATEGORIES.filter((c) => c.active !== false && enUso.has(c.name))
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((c) => c.name);
    const sueltas = [...enUso].filter((n) => !conocidas.has(n)).sort();
    return [...orden, ...sueltas];
  }

  function renderChips() {
    const cats = orderedCategories();
    const el = $("chips");
    el.innerHTML = "";
    const mk = (label, value) => {
      const b = document.createElement("button");
      b.className = "chip";
      b.type = "button";
      b.textContent = label;
      b.setAttribute("aria-pressed", String(categoryFilter === value));
      b.onclick = () => { categoryFilter = value; renderChips(); renderGrid(); };
      return b;
    };
    el.appendChild(mk("Ver todos", null));
    for (const c of cats) el.appendChild(mk(c, c));
  }

  // ---- Rejilla ----
  function visibleProducts() {
    const q = query.trim().toLowerCase();
    let list = PRODUCTS.filter((p) => {
      if (categoryFilter != null && p.category !== categoryFilter) return false;
      if (q && !(p.name + " " + (p.description || "") + " " + (p.brand || ""))
        .toLowerCase().includes(q)) return false;
      return true;
    });
    const price = (p) => priceOf(p.id) ?? Number.MAX_SAFE_INTEGER;
    if (sortBy === "price-asc") list = list.slice().sort((a, b) => price(a) - price(b));
    else if (sortBy === "price-desc") list = list.slice().sort((a, b) => price(b) - price(a));
    else if (sortBy === "name-asc") list = list.slice().sort((a, b) => a.name.localeCompare(b.name, "es"));
    else if (sortBy === "name-desc") list = list.slice().sort((a, b) => b.name.localeCompare(a.name, "es"));
    return list;
  }

  function thumbHtml(p) {
    const imgs = imagesOf(p.id);
    if (!imgs.length) return '<div class="thumb"></div>';
    return '<div class="thumb"><img src="' + esc(imgs[0]) + '" alt="' + esc(p.name) +
      '" loading="lazy" /></div>';
  }

  function renderGrid() {
    const grid = $("grid");
    const list = visibleProducts();
    grid.classList.toggle("list", listView);
    if (!list.length) {
      $("state").hidden = false;
      $("state").textContent = query
        ? 'Sin resultados para "' + query + '".'
        : "No hay productos en esta categoría.";
      grid.innerHTML = "";
      return;
    }
    $("state").hidden = true;
    grid.innerHTML = "";
    for (const p of list) {
      const soldOut = stockOf(p.id) <= 0;
      const price = priceOf(p.id);
      const card = document.createElement("article");
      card.className = "card" + (soldOut ? " soldout" : "");
      card.innerHTML =
        thumbHtml(p) +
        "<div>" +
        "<h3>" + esc(p.name) + "</h3>" +
        (p.description ? '<p class="desc">' + esc(p.description) + "</p>" : "") +
        (soldOut
          ? '<p class="out">Producto agotado</p>'
          : '<p class="price">' + money(price) + "</p>") +
        "</div>" +
        (soldOut ? "" : '<button class="addmini" type="button">Agregar al carrito</button>');
      card.querySelector(".thumb").onclick = () => openDetail(p);
      card.querySelector("h3").onclick = () => openDetail(p);
      const add = card.querySelector(".addmini");
      if (add) {
        add.onclick = (e) => {
          e.stopPropagation();
          const vs = variantsOf(p.id).filter((v) => v.stock > 0);
          // Con una sola variante disponible se agrega directo; si hay talla o
          // color que elegir, se abre la ficha para no adivinar por el cliente.
          if (vs.length === 1) { addToCart(p, vs[0], 1); toast("Agregado al carrito"); }
          else openDetail(p);
        };
      }
      grid.appendChild(card);
    }
  }

  // ---- Ficha de producto ----
  function variantLabel(v) {
    return [v.size, v.color].filter(Boolean).join(" · ") || (v.sku || "Único");
  }

  function openDetail(p) {
    current = p;
    const vs = variantsOf(p.id);
    currentVariant = vs.find((v) => v.stock > 0) || vs[0] || null;
    $("dName").textContent = p.name;
    $("dDesc").textContent = p.description || "";
    $("dDesc").hidden = !p.description;
    $("dQty").value = "1";

    // Galería: si no hay fotos, un marcador para no dejar el hueco vacío.
    const imgs = imagesOf(p.id);
    const strip = $("dStrip");
    strip.innerHTML = imgs.length
      ? imgs.map((u, i) =>
          '<img src="' + esc(u) + '" alt="Imagen ' + (i + 1) + " de " + esc(p.name) + '" />').join("")
      : '<div style="flex:0 0 100%;aspect-ratio:1/1"></div>';
    const dots = $("dDots");
    dots.innerHTML = imgs.length > 1
      ? imgs.map((_, i) => '<span class="dot' + (i === 0 ? " on" : "") + '"></span>').join("")
      : "";
    strip.onscroll = () => {
      if (imgs.length < 2) return;
      const i = Math.round(strip.scrollLeft / strip.clientWidth);
      dots.querySelectorAll(".dot").forEach((d, k) => d.classList.toggle("on", k === i));
    };

    // Escalones de mayoreo, si el producto los tiene.
    const tiers = (TIERS.get(p.id) || []).slice().sort((a, b) => a.min_qty - b.min_qty);
    const tEl = $("dTiers");
    tEl.hidden = !tiers.length;
    if (tiers.length) {
      tEl.textContent = "Mayoreo: " +
        tiers.map((t) => "desde " + t.min_qty + " a " + money(t.price_cents) + " c/u").join("  ·  ");
    }

    drawVariants();
    $("detail").hidden = false;
    document.body.style.overflow = "hidden";
  }

  function drawVariants() {
    const vs = variantsOf(current.id);
    const box = $("dVariants");
    // Con una sola variante sin talla ni color no hay nada que elegir.
    const trivial = vs.length <= 1 && !(vs[0] && (vs[0].size || vs[0].color));
    box.hidden = trivial;
    box.innerHTML = trivial ? "" : vs.map((v) =>
      '<button class="vbtn" type="button" data-v="' + v.id + '"' +
      (v.stock <= 0 ? " disabled" : "") +
      ' aria-pressed="' + String(currentVariant && v.id === currentVariant.id) + '">' +
      esc(variantLabel(v)) + "</button>").join("");
    box.querySelectorAll("[data-v]").forEach((b) => {
      b.onclick = () => {
        currentVariant = vs.find((v) => String(v.id) === b.dataset.v);
        drawVariants();
        drawAddTotal();
      };
    });
    drawAddTotal();
  }

  function drawAddTotal() {
    const max = currentVariant ? currentVariant.stock : 0;
    // Se recorta la cantidad al stock: el carrito ya lo hace al agregar, y sin
    // esto el botón prometía un total ("$3,600") que no se iba a respetar.
    let qty = Math.max(1, parseInt($("dQty").value, 10) || 1);
    if (max > 0 && qty > max) { qty = max; $("dQty").value = String(max); }
    const price = currentVariant ? currentVariant.price_cents : priceOf(current.id) || 0;
    $("dPrice").textContent = money(price);
    $("dAddTotal").textContent = money(price * qty);
    $("dAdd").disabled = !currentVariant || max <= 0;
  }

  function closeDetail() {
    $("detail").hidden = true;
    document.body.style.overflow = "";
    renderGrid();
  }

  // ---- Carrito ----
  function renderCartCount() {
    const n = cartCount();
    const el = $("cartCount");
    el.textContent = String(n);
    el.hidden = n === 0;
  }

  function openCart() {
    const lines = pricedCart();
    const body = $("cartBody");
    if (!lines.length) {
      body.innerHTML = '<p class="empty">Tu carrito está vacío.</p>';
      $("cartTotals").innerHTML = "";
      $("checkout").disabled = true;
    } else {
      body.innerHTML = lines.map((l) => {
        const img = imagesOf(l.product.id)[0];
        const meta = [l.variant.size, l.variant.color].filter(Boolean).join(" · ");
        return '<div class="cline">' +
          (img ? '<img src="' + esc(img) + '" alt="" />' : '<img alt="" />') +
          '<div class="cinfo">' +
          '<p class="cname">' + esc(l.product.name) + "</p>" +
          '<p class="cmeta">' + (meta ? esc(meta) + " · " : "") + l.qty + " × " + money(l.unit) +
          (l.wholesale ? " · mayoreo" : "") + "</p>" +
          "</div>" +
          '<span class="cprice">' + money(l.lineTotal) + "</span>" +
          '<button class="icon" data-del="' + l.variant.id + '" aria-label="Quitar">' +
          '<svg viewBox="0 0 24 24"><path d="M5 7h14M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>' +
          "</button></div>";
      }).join("");
      body.querySelectorAll("[data-del]").forEach((b) => {
        b.onclick = () => { cart.delete(Number(b.dataset.del)); renderCartCount(); openCart(); };
      });
      const n = cartCount();
      $("cartTotals").innerHTML =
        "<div><span>" + n + (n === 1 ? " artículo" : " artículos") + "</span><span></span></div>" +
        '<div class="grand"><span>Total</span><span>' + money(cartTotal()) + "</span></div>";
      $("checkout").disabled = false;
    }
    $("cartSheet").hidden = false;
    document.body.style.overflow = "hidden";
  }

  function closeCart() {
    $("cartSheet").hidden = true;
    document.body.style.overflow = "";
    renderGrid();
  }

  // ---- Datos de contacto ----
  const isDelivery = () =>
    document.querySelector('input[name="entrega"]:checked')?.value === "delivery";

  function openCheckout() {
    $("cartSheet").hidden = true;
    $("checkoutSheet").hidden = false;
    document.body.style.overflow = "hidden";
    syncDelivery();
    drawCheckoutTotal();
  }

  function closeCheckout() {
    $("checkoutSheet").hidden = true;
    openCart();
  }

  /// La dirección solo aplica a domicilio: si el pedido es para recoger, ni se
  /// pide ni se valida.
  function syncDelivery() {
    const dom = isDelivery();
    $("addrBox").hidden = !dom;
    if (!dom) clearError("coAddr", "errAddr");
  }

  function drawCheckoutTotal() {
    const n = cartCount();
    $("coCount").textContent = String(n);
    $("coTotal").textContent = money(cartTotal());
  }

  function markError(inputId, errId, bad) {
    $(inputId).classList.toggle("bad", bad);
    $(errId).hidden = !bad;
  }
  function clearError(inputId, errId) { markError(inputId, errId, false); }

  /** Valida y devuelve los datos, o `null` si algo falta. */
  function readContact() {
    const name = $("coName").value.trim();
    // Se compara por dígitos: el cliente puede escribir 899-703-49-22.
    const phoneDigits = $("coPhone").value.replace(/\D/g, "");
    const addr = $("coAddr").value.trim();
    const dom = isDelivery();

    const badName = name.length < 2;
    const badPhone = phoneDigits.length < 10;
    const badAddr = dom && addr.length < 5;
    markError("coName", "errName", badName);
    markError("coPhone", "errPhone", badPhone);
    if (dom) markError("coAddr", "errAddr", badAddr);

    if (badName || badPhone || badAddr) {
      const first = badName ? "coName" : badPhone ? "coPhone" : "coAddr";
      $(first).focus();
      return null;
    }
    return {
      name,
      phone: phoneDigits,
      addr,
      delivery: dom,
      notes: $("coNotes").value.trim(),
    };
  }

  // ---- Pedido por WhatsApp ----
  /** Arma el mensaje del pedido, listo para pegar en el chat de la tienda. */
  function orderMessage(contact) {
    const lines = pricedCart();
    const out = [
      `*Pedido ${CFG.SHOP_NAME || ""}*`.trim(),
      "",
      ...lines.map((l) => {
        const meta = [l.variant.size, l.variant.color].filter(Boolean).join(" ");
        return `• ${l.qty} x ${l.product.name}${meta ? " (" + meta + ")" : ""}` +
          `${l.wholesale ? " [mayoreo]" : ""} — ${money(l.lineTotal)}`;
      }),
      "",
      `*Total: ${money(cartTotal())}*`,
      "",
      contact.delivery
        ? `Entrega a domicilio: ${contact.addr}`
        : "Para llevar / Recoger en tienda",
      `Nombre: ${contact.name}`,
      `Celular: ${contact.phone}`,
    ];
    if (contact.notes) out.push(`Comentarios: ${contact.notes}`);
    return out.join("\n");
  }

  function openPay() {
    $("checkoutSheet").hidden = true;
    $("paySheet").hidden = false;
  }

  function closePay() {
    $("paySheet").hidden = true;
    $("checkoutSheet").hidden = false;
  }

  function sendWhatsApp() {
    const contact = readContact();
    if (!contact) { closePay(); return; }
    const phone = (CFG.WHATSAPP || "").replace(/\D/g, "");
    if (!phone) { toast("Falta configurar el WhatsApp de la tienda"); return; }
    const url = "https://wa.me/" + phone + "?text=" +
      encodeURIComponent(orderMessage(contact));
    // `noopener` por seguridad al abrir en pestaña nueva.
    window.open(url, "_blank", "noopener");
  }

  // ---- Pago con Mercado Pago (Checkout Pro) ----
  /** Crea la preferencia en el servidor y redirige al checkout de Mercado Pago. */
  async function payMercadoPago() {
    const contact = readContact();
    if (!contact) { closePay(); return; }
    const items = pricedCart().map((l) => {
      const meta = [l.variant.size, l.variant.color].filter(Boolean).join(" ");
      return {
        title: l.product.name + (meta ? " (" + meta + ")" : "") +
          (l.wholesale ? " [mayoreo]" : ""),
        quantity: l.qty,
        unit_price: l.unit / 100, // pesos
      };
    });
    if (!items.length) return;
    const btn = $("payMp");
    btn.disabled = true;
    toast("Preparando el pago…");
    try {
      const res = await fetch(CFG.SUPABASE_URL + "/functions/v1/create-preference", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: CFG.SUPABASE_ANON,
          Authorization: "Bearer " + CFG.SUPABASE_ANON,
        },
        body: JSON.stringify({
          items,
          customer: contact,
          store_url: location.origin + location.pathname,
        }),
      });
      const data = await res.json().catch(() => ({}));
      const target = data.init_point || data.sandbox_init_point;
      if (!res.ok || !target) {
        toast(data.error || "No se pudo iniciar el pago");
        btn.disabled = false;
        return;
      }
      window.location.href = target; // al checkout seguro de Mercado Pago
    } catch (_) {
      toast("Error de red al iniciar el pago");
      btn.disabled = false;
    }
  }

  /** Al volver de Mercado Pago (?pago=exito/error/pendiente) avisa y limpia. */
  function handlePaymentReturn() {
    const p = new URLSearchParams(location.search).get("pago");
    if (!p) return;
    if (p === "exito") {
      cart.clear();
      renderCartCount();
      toast("¡Pago recibido! Gracias por tu compra 🧢");
    } else if (p === "pendiente") {
      toast("Tu pago quedó pendiente de confirmación.");
    } else {
      toast("El pago no se completó.");
    }
    // Limpia el parámetro para que no reaparezca al recargar.
    history.replaceState(null, "", location.origin + location.pathname);
  }

  // ---- Arranque ----
  function wire() {
    $("search").oninput = (e) => { query = e.target.value; renderGrid(); };
    $("sort").onchange = (e) => { sortBy = e.target.value; renderGrid(); };
    $("viewGrid").onclick = () => {
      listView = false;
      $("viewGrid").classList.add("on"); $("viewList").classList.remove("on");
      renderGrid();
    };
    $("viewList").onclick = () => {
      listView = true;
      $("viewList").classList.add("on"); $("viewGrid").classList.remove("on");
      renderGrid();
    };
    $("brandHome").onclick = (e) => {
      e.preventDefault();
      categoryFilter = null; query = ""; $("search").value = "";
      renderChips(); renderGrid(); window.scrollTo({ top: 0, behavior: "smooth" });
    };

    $("dBack").onclick = closeDetail;
    $("detail").onclick = (e) => { if (e.target === $("detail")) closeDetail(); };
    $("dCart").onclick = () => { closeDetail(); openCart(); };
    $("dMinus").onclick = () => {
      $("dQty").value = String(Math.max(1, (parseInt($("dQty").value, 10) || 1) - 1));
      drawAddTotal();
    };
    $("dPlus").onclick = () => {
      const max = currentVariant ? currentVariant.stock : 1;
      $("dQty").value = String(Math.min(max, (parseInt($("dQty").value, 10) || 1) + 1));
      drawAddTotal();
    };
    $("dQty").oninput = drawAddTotal;
    $("dAdd").onclick = () => {
      if (!currentVariant) return;
      const qty = Math.max(1, parseInt($("dQty").value, 10) || 1);
      addToCart(current, currentVariant, qty);
      closeDetail();
      toast("Agregado al carrito");
    };

    $("cartBtn").onclick = openCart;
    $("cBack").onclick = closeCart;
    $("cartSheet").onclick = (e) => { if (e.target === $("cartSheet")) closeCart(); };
    $("checkout").onclick = openCheckout;
    $("coBack").onclick = closeCheckout;
    $("checkoutSheet").onclick = (e) => {
      if (e.target === $("checkoutSheet")) closeCheckout();
    };
    for (const r of document.querySelectorAll('input[name="entrega"]')) {
      r.onchange = syncDelivery;
    }
    $("coSend").onclick = () => { if (readContact()) openPay(); };
    $("payBack").onclick = closePay;
    $("paySheet").onclick = (e) => { if (e.target === $("paySheet")) closePay(); };
    $("payWa").onclick = sendWhatsApp;

    $("footShipping").onclick = openShipping;
    $("coShipping").onclick = openShipping;
    $("shipBack").onclick = closeShipping;
    $("shippingSheet").onclick = (e) => {
      if (e.target === $("shippingSheet")) closeShipping();
    };

    // Mercado Pago: el botón solo aparece si está habilitado en config.js
    // (es decir, cuando ya están desplegadas las Edge Functions y el secreto).
    const mpBtn = $("payMp");
    if (mpBtn) {
      if (CFG.MP_ENABLED) {
        mpBtn.disabled = false;
        mpBtn.onclick = payMercadoPago;
        const small = mpBtn.querySelector("small");
        if (small) small.remove();
      } else {
        mpBtn.hidden = true;
      }
    }
    // Avisa si venimos de regreso del checkout de Mercado Pago.
    handlePaymentReturn();

    document.onkeydown = (e) => {
      if (e.key !== "Escape") return;
      if (!$("detail").hidden) closeDetail();
      else if (!$("shippingSheet").hidden) closeShipping();
      else if (!$("paySheet").hidden) closePay();
      else if (!$("checkoutSheet").hidden) closeCheckout();
      else if (!$("cartSheet").hidden) closeCart();
    };
  }

  async function init() {
    renderShopBar();
    wire();
    renderCartCount();

    // La tarjeta digital (Admin → Tarjeta digital) es la fuente editable de
    // la FAQ de envíos; sin ella (o sin el SQL 0006) se usa `config.js`.
    let cardData = null;
    try {
      const rows = await rest("business_card?select=data&id=eq.1");
      cardData = rows && rows[0] ? rows[0].data : null;
    } catch (_) {
      // Sin tabla `business_card`: renderShipping cae a CFG.SHIPPING.
    }
    renderShipping(cardData);

    // Los anuncios se piden aparte y primero: son lo primero que se ve, y si
    // el catálogo tardara no tiene por qué retrasarlos.
    try {
      applyPublishedBanners(
          await rest("catalog_banners?select=*&order=position.asc"));
    } catch (_) {
      // Sin tabla de anuncios (proyecto sin el SQL 0004) se usan los de ejemplo.
    }
    renderCover();
    renderBanners();

    try {
      const [products, variants, tiers, images, categories] = await Promise.all([
        rest("catalog_products?select=*&active=eq.true&order=name.asc"),
        rest("catalog_variants?select=*&active=eq.true"),
        rest("catalog_price_tiers?select=*"),
        rest("catalog_images?select=*&order=position.asc").catch(() => []),
        // Sin el SQL 0007 esta tabla no existe: se sigue sin ella (categorías
        // deducidas de los productos, alfabéticas).
        rest("catalog_categories?select=*&order=position.asc").catch(() => []),
      ]);
      PRODUCTS = products;
      CATEGORIES = Array.isArray(categories) ? categories : [];
      VARIANTS = new Map(); TIERS = new Map(); IMAGES = new Map();
      const push = (map, key, val) => {
        if (!map.has(key)) map.set(key, []);
        map.get(key).push(val);
      };
      for (const v of variants) push(VARIANTS, v.product_id, v);
      for (const t of tiers) push(TIERS, t.product_id, t);
      for (const im of images) push(IMAGES, im.product_id, im.url);

      if (!PRODUCTS.length) {
        $("state").textContent =
          "El catálogo está vacío. Publícalo desde el POS (Admin → Catálogo web).";
        return;
      }
      renderChips();
      renderGrid();
    } catch (e) {
      $("state").textContent = "No se pudo cargar el catálogo: " + e.message;
    }
  }

  init();
})();
