/* Tienda web (solo lectura del catálogo). El carrito y el mayoreo replican la
 * lógica del POS. El cobro (Mercado Pago) se enchufa en la fase #8. */
(function () {
  "use strict";
  const CFG = window.CATALOGO_CONFIG;
  const HEADERS = {
    apikey: CFG.SUPABASE_ANON,
    Authorization: "Bearer " + CFG.SUPABASE_ANON,
  };

  // Estado
  let PRODUCTS = [];
  let VARIANTS_BY_PRODUCT = new Map(); // productId -> [variant]
  let TIERS_BY_PRODUCT = new Map(); // productId -> [tier]
  let categoryFilter = null; // null = todas
  const cart = new Map(); // variantId -> { qty, variant, product }

  const $ = (id) => document.getElementById(id);
  const money = (c) => "$" + (c / 100).toFixed(2);

  async function rest(path) {
    const res = await fetch(CFG.SUPABASE_URL + "/rest/v1/" + path, { headers: HEADERS });
    if (!res.ok) throw new Error("HTTP " + res.status);
    return res.json();
  }

  /** Precio de mayoreo aplicable para `qty` piezas, o null si ninguno aplica. */
  function wholesalePriceFor(tiers, qty) {
    let best = null, bestMin = -1;
    for (const t of tiers || []) {
      if (qty >= t.min_qty && t.min_qty > bestMin) { bestMin = t.min_qty; best = t.price_cents; }
    }
    return best;
  }

  function retailPrice(variant) { return variant.price_cents; }

  /** Precio "desde" (menor menudeo) de un producto, para la tarjeta. */
  function fromPrice(productId) {
    const vs = VARIANTS_BY_PRODUCT.get(productId) || [];
    if (!vs.length) return null;
    return Math.min(...vs.map(retailPrice));
  }

  // ---- Carrito / mayoreo ----
  function aggregateQtyByProduct() {
    const m = new Map();
    for (const { qty, product } of cart.values()) {
      m.set(product.id, (m.get(product.id) || 0) + qty);
    }
    return m;
  }

  /** Devuelve líneas del carrito con precio efectivo (menudeo o mayoreo). */
  function pricedCart() {
    const agg = aggregateQtyByProduct();
    const lines = [];
    for (const entry of cart.values()) {
      const tiers = TIERS_BY_PRODUCT.get(entry.product.id);
      const w = wholesalePriceFor(tiers, agg.get(entry.product.id) || 0);
      const unit = w != null ? w : retailPrice(entry.variant);
      lines.push({ ...entry, unit, wholesale: w != null, lineTotal: unit * entry.qty });
    }
    return lines;
  }

  function cartCount() {
    let n = 0; for (const e of cart.values()) n += e.qty; return n;
  }
  function cartTotal() {
    return pricedCart().reduce((s, l) => s + l.lineTotal, 0);
  }

  function addToCart(product, variant, delta) {
    const cur = cart.get(variant.id);
    const qty = (cur ? cur.qty : 0) + delta;
    if (qty <= 0) cart.delete(variant.id);
    else cart.set(variant.id, { qty, variant, product });
    renderCartBar();
  }

  // ---- Render ----
  function renderCategories() {
    const cats = [...new Set(PRODUCTS.map((p) => p.category).filter(Boolean))].sort();
    const el = $("cats");
    el.innerHTML = "";
    const mk = (label, value) => {
      const b = document.createElement("button");
      b.className = "chip" + (categoryFilter === value ? " active" : "");
      b.textContent = label;
      b.onclick = () => { categoryFilter = value; renderCategories(); renderGrid(); };
      return b;
    };
    el.appendChild(mk("Todo", null));
    for (const c of cats) el.appendChild(mk(c, c));
  }

  function renderGrid() {
    const grid = $("grid");
    const list = PRODUCTS.filter((p) => categoryFilter == null || p.category === categoryFilter);
    if (!list.length) {
      grid.innerHTML = '<div class="empty">No hay productos en esta categoría.</div>';
      return;
    }
    grid.innerHTML = "";
    for (const p of list) {
      const card = document.createElement("div");
      card.className = "card";
      const from = fromPrice(p.id);
      const tiers = TIERS_BY_PRODUCT.get(p.id) || [];
      const minTier = tiers.length ? Math.min(...tiers.map((t) => t.min_qty)) : null;
      card.innerHTML =
        '<div class="thumb">🧢</div>' +
        '<div class="info">' +
        '<div class="name">' + esc(p.name) + "</div>" +
        (from != null ? '<div class="price">desde ' + money(from) + "</div>" : "") +
        (minTier != null ? '<div class="mayoreo-tag">Mayoreo desde ' + minTier + "</div>" : "") +
        "</div>";
      card.onclick = () => openVariantSheet(p);
      grid.appendChild(card);
    }
  }

  function openVariantSheet(product) {
    const vs = (VARIANTS_BY_PRODUCT.get(product.id) || []).slice();
    const tiers = TIERS_BY_PRODUCT.get(product.id) || [];
    const sheet = $("variantSheet");

    function draw() {
      const tierTxt = tiers
        .slice().sort((a, b) => a.min_qty - b.min_qty)
        .map((t) => "desde " + t.min_qty + " → " + money(t.price_cents)).join("  ·  ");
      sheet.innerHTML =
        '<button class="close-x" data-close>×</button>' +
        "<h2>" + esc(product.name) + "</h2>" +
        '<div class="sub">' + esc(product.brand || product.category || "") + "</div>" +
        (tierTxt ? '<div class="mayoreo-note">⚡ Mayoreo: ' + tierTxt + " (surtido entre variantes)</div>" : "") +
        vs.map((v) => {
          const cur = cart.get(v.id);
          const q = cur ? cur.qty : 0;
          const meta = [v.size, v.color].filter(Boolean).join(" · ");
          const stockTxt = v.stock <= 0 ? '<span class="out">Agotado</span>' : "existencia " + v.stock;
          return (
            '<div class="variant-row">' +
            '<div><div class="v-name">' + money(retailPrice(v)) + (meta ? " — " + esc(meta) : "") +
            '</div><div class="v-meta">' + stockTxt + "</div></div>" +
            '<div class="stepper">' +
            '<button data-dec="' + v.id + '" ' + (q <= 0 ? "disabled" : "") + ">−</button>" +
            '<span class="qty">' + q + "</span>" +
            '<button data-inc="' + v.id + '" ' + (v.stock <= 0 || q >= v.stock ? "disabled" : "") + ">+</button>" +
            "</div></div>"
          );
        }).join("") +
        '<button class="btn" data-close>Listo</button>';

      sheet.querySelectorAll("[data-inc]").forEach((b) =>
        (b.onclick = () => { const v = vs.find((x) => x.id == b.dataset.inc); addToCart(product, v, +1); draw(); }));
      sheet.querySelectorAll("[data-dec]").forEach((b) =>
        (b.onclick = () => { const v = vs.find((x) => x.id == b.dataset.dec); addToCart(product, v, -1); draw(); }));
      sheet.querySelectorAll("[data-close]").forEach((b) => (b.onclick = closeSheets));
    }
    draw();
    $("variantBackdrop").hidden = false;
  }

  function openCartSheet() {
    const sheet = $("cartSheet");
    function draw() {
      const lines = pricedCart();
      if (!lines.length) { closeSheets(); return; }
      sheet.innerHTML =
        '<button class="close-x" data-close>×</button>' +
        "<h2>Tu pedido</h2>" +
        lines.map((l) => {
          const meta = [l.variant.size, l.variant.color].filter(Boolean).join(" · ");
          return (
            '<div class="cart-line"><div>' +
            "<div>" + esc(l.product.name) + (meta ? " (" + esc(meta) + ")" : "") +
            (l.wholesale ? '<span class="badge-mayoreo">MAYOREO</span>' : "") + "</div>" +
            '<div class="cl-sub">' + l.qty + " × " + money(l.unit) + "</div></div>" +
            "<div>" + money(l.lineTotal) + "</div></div>"
          );
        }).join("") +
        '<div class="totrow"><span>Total</span><span class="tot">' + money(cartTotal()) + "</span></div>" +
        '<button class="btn" id="checkoutBtn">Continuar al pago</button>' +
        '<button class="btn secondary" data-close>Seguir comprando</button>';
      sheet.querySelectorAll("[data-close]").forEach((b) => (b.onclick = closeSheets));
      $("checkoutBtn").onclick = checkout;
    }
    draw();
    $("cartBackdrop").hidden = false;
  }

  function checkout() {
    // #8: aquí se creará la preferencia de Mercado Pago y se redirige al pago.
    alert("El pago con Mercado Pago se habilita en la siguiente fase.\nTotal: " + money(cartTotal()));
  }

  function closeSheets() {
    $("variantBackdrop").hidden = true;
    $("cartBackdrop").hidden = true;
    renderGrid(); // refresca etiquetas
    renderCartBar();
  }

  function renderCartBar() {
    $("cartCount").textContent = cartCount();
    let bar = $("cartbar");
    if (!bar) {
      bar = document.createElement("div");
      bar.id = "cartbar";
      bar.className = "cartbar";
      document.body.appendChild(bar);
    }
    const n = cartCount();
    if (n <= 0) { bar.classList.add("hidden"); return; }
    bar.classList.remove("hidden");
    bar.innerHTML =
      '<div class="cb-total"><small>' + n + " artículo(s)</small><b>" + money(cartTotal()) + "</b></div>" +
      '<button class="btn" id="openCart">Ver pedido</button>';
    $("openCart").onclick = openCartSheet;
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, (m) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));
  }

  async function init() {
    $("shopName").textContent = CFG.SHOP_NAME || "Catálogo";
    document.title = CFG.SHOP_NAME || "Catálogo";
    $("cartBtn").onclick = () => { if (cartCount() > 0) openCartSheet(); };
    document.querySelectorAll(".sheet-backdrop").forEach((bd) => {
      bd.onclick = (e) => { if (e.target === bd) closeSheets(); };
    });
    try {
      const [products, variants, tiers] = await Promise.all([
        rest("catalog_products?select=*&active=eq.true&order=name.asc"),
        rest("catalog_variants?select=*&active=eq.true"),
        rest("catalog_price_tiers?select=*"),
      ]);
      PRODUCTS = products;
      VARIANTS_BY_PRODUCT = new Map();
      for (const v of variants) {
        if (!VARIANTS_BY_PRODUCT.has(v.product_id)) VARIANTS_BY_PRODUCT.set(v.product_id, []);
        VARIANTS_BY_PRODUCT.get(v.product_id).push(v);
      }
      TIERS_BY_PRODUCT = new Map();
      for (const t of tiers) {
        if (!TIERS_BY_PRODUCT.has(t.product_id)) TIERS_BY_PRODUCT.set(t.product_id, []);
        TIERS_BY_PRODUCT.get(t.product_id).push(t);
      }
      if (!PRODUCTS.length) {
        $("grid").innerHTML = '<div class="empty">El catálogo está vacío.<br/>Publícalo desde el POS (Admin → Catálogo web).</div>';
      } else {
        renderCategories();
        renderGrid();
      }
      renderCartBar();
    } catch (e) {
      $("grid").innerHTML = '<div class="empty">No se pudo cargar el catálogo.<br/>' + esc(e.message) + "</div>";
    }
  }

  init();
})();
