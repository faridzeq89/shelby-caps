// Edge Function: procesa un pago de tarjeta con Mercado Pago (Checkout Bricks /
// Checkout transparente). El cliente NUNCA sale de la tienda: el Payment Brick
// tokeniza la tarjeta en el navegador y manda aquí el token; este servidor
// crea el pago real y confirma.
//
// A diferencia de `create-preference` (Checkout Pro, que redirige), aquí el
// precio se **recalcula desde el catálogo publicado** (catalog_variants /
// catalog_products / catalog_settings): el cliente solo manda variant_id + qty,
// nunca el precio. Así un carrito manipulado no puede pagar de menos.
//
// Secretos que necesita (se ponen con `supabase secrets set`, NO van en el repo):
//   MP_ACCESS_TOKEN   -> Access Token de Mercado Pago (TEST-... en sandbox)
// Ya vienen inyectados por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Desplegar:
//   supabase functions deploy process-payment

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const peso = (n: number) =>
  "$" + n.toLocaleString("es-MX", { maximumFractionDigits: 2 });
const esc = (s: string) =>
  s.replace(/[&<>"]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[m]!));

/// Envía los correos de confirmación por Resend. **No-op** si no está
/// configurado `RESEND_API_KEY`, así que es seguro desplegar sin la llave.
/// Best-effort: cualquier fallo aquí NO debe afectar el cobro.
async function sendConfirmationEmails(opts: {
  toCustomer: string;
  orderId: string;
  items: Array<Record<string, unknown>>;
  totalCents: number;
  customer: { name: string; phone: string; email: string; addr: string; delivery: boolean };
  approved: boolean;
}): Promise<void> {
  const KEY = Deno.env.get("RESEND_API_KEY");
  if (!KEY) return; // sin configurar => no se manda nada
  const FROM = Deno.env.get("MAIL_FROM") || "Shelby Caps <onboarding@resend.dev>";
  const STORE = Deno.env.get("STORE_EMAIL");
  const ref = opts.orderId.slice(0, 8).toUpperCase();

  const rows = opts.items
    .map((it) => {
      const line = Number(it.unit_price) * Number(it.quantity);
      return `<tr><td style="padding:6px 0;border-bottom:1px solid #eee">${
        it.quantity
      } × ${esc(String(it.title))}</td><td style="padding:6px 0;border-bottom:1px solid #eee;text-align:right;white-space:nowrap">${
        peso(line)
      }</td></tr>`;
    })
    .join("");
  const entrega = opts.customer.delivery
    ? "Envío a domicilio: " + esc(opts.customer.addr)
    : "Recoger en tienda";
  const total = peso(opts.totalCents / 100);

  const wrap = (title: string, bodyHtml: string) => `
<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#171717">
  <div style="background:#a81c22;color:#fff;padding:16px 20px;border-radius:10px 10px 0 0">
    <div style="font-size:20px;font-weight:800;letter-spacing:1px">SHELBY CAPS</div>
  </div>
  <div style="border:1px solid #e7e7e7;border-top:0;border-radius:0 0 10px 10px;padding:20px">
    <h2 style="margin:0 0 6px">${title}</h2>
    ${bodyHtml}
    <table style="width:100%;border-collapse:collapse;margin:14px 0">${rows}
      <tr><td style="padding:10px 0 0;font-weight:800">Total</td>
      <td style="padding:10px 0 0;text-align:right;font-weight:800">${total}</td></tr>
    </table>
    <p style="margin:6px 0;color:#6b6b6b;font-size:14px">${entrega}</p>
    <p style="margin:14px 0 0;color:#6b6b6b;font-size:12px">N.º de pedido: <b>${ref}</b></p>
  </div>
</div>`;

  const customerHtml = wrap(
    opts.approved ? "¡Gracias por tu compra!" : "Recibimos tu pedido",
    `<p style="margin:0 0 4px;font-size:15px">${
      opts.approved
        ? "Tu pago fue aprobado. Nos pondremos en contacto contigo para coordinar la entrega."
        : "Tu pago está en revisión. En cuanto se confirme te avisamos."
    }</p>`,
  );
  const storeHtml = wrap(
    "Nuevo pedido" + (opts.approved ? "" : " (en revisión)"),
    `<p style="margin:0;font-size:15px">
       <b>Cliente:</b> ${esc(opts.customer.name)}<br>
       <b>Tel:</b> ${esc(opts.customer.phone)}<br>
       <b>Correo:</b> ${esc(opts.customer.email)}
     </p>`,
  );

  const send = (to: string, subject: string, html: string) =>
    fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: FROM, to, subject, html }),
    });

  const jobs: Promise<unknown>[] = [];
  if (opts.approved && opts.toCustomer) {
    jobs.push(send(opts.toCustomer, `Tu compra en Shelby Caps — Pedido ${ref}`, customerHtml));
  }
  if (STORE) {
    jobs.push(send(STORE, `Nuevo pedido ${ref}${opts.approved ? "" : " (en revisión)"}`, storeHtml));
  }
  await Promise.allSettled(jobs);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "método no permitido" }, 405);

  try {
    const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN");
    if (!MP_TOKEN) return json({ error: "Falta MP_ACCESS_TOKEN" }, 500);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json().catch(() => ({}));
    // El Payment Brick manda su `formData` con token, método, cuotas y pagador.
    const form = (body.form_data ?? body.formData ?? {}) as Record<string, unknown>;
    const rawCart = Array.isArray(body.cart) ? body.cart : [];
    if (rawCart.length === 0) return json({ error: "El carrito está vacío" }, 400);
    if (!form.token) return json({ error: "Falta el token de la tarjeta" }, 400);

    // -----------------------------------------------------------------------
    // 1) Precio AUTORITATIVO desde el catálogo publicado. El cliente manda
    //    variant_id + qty; el precio y el mayoreo se leen de la base.
    // -----------------------------------------------------------------------
    const wanted = new Map<number, number>(); // variantId -> qty
    for (const c of rawCart) {
      const id = parseInt(String((c as Record<string, unknown>).variant_id));
      const qty = Math.max(1, parseInt(String((c as Record<string, unknown>).qty)) || 1);
      if (Number.isFinite(id)) wanted.set(id, (wanted.get(id) ?? 0) + qty);
    }
    if (wanted.size === 0) return json({ error: "Carrito inválido" }, 400);

    const ids = [...wanted.keys()];
    const { data: variants, error: vErr } = await supabase
      .from("catalog_variants")
      .select("id, product_id, price_cents")
      .in("id", ids)
      .eq("active", true);
    if (vErr) return json({ error: "Catálogo: " + vErr.message }, 500);
    const vById = new Map((variants ?? []).map((v) => [v.id as number, v]));

    const productIds = [...new Set((variants ?? []).map((v) => v.product_id as number))];
    const { data: products } = await supabase
      .from("catalog_products")
      .select("id, name, wholesale_price_cents, discount_kind, discount_value")
      .in("id", productIds);
    const pById = new Map((products ?? []).map((p) => [p.id as number, p]));

    // Descuento de oferta por producto (misma regla que el POS y la tienda).
    const offer = (base: number, kind: unknown, value: unknown): number => {
      const v = Number(value) || 0;
      if (!kind || v <= 0) return base;
      const off = kind === "percent" ? Math.round(base * v / 100) : v;
      return Math.max(0, base - off);
    };

    // Umbral de mayoreo (si la tabla no existe todavía, sin mayoreo).
    let threshold = 0;
    const { data: settings } = await supabase
      .from("catalog_settings")
      .select("wholesale_threshold")
      .limit(1);
    if (settings && settings.length > 0) {
      threshold = Number(settings[0].wholesale_threshold) || 0;
    }

    let pieces = 0;
    for (const [id, qty] of wanted) if (vById.has(id)) pieces += qty;
    const wholesaleActive = threshold > 0 && pieces >= threshold;

    let totalCents = 0;
    const items: Array<Record<string, unknown>> = [];
    for (const [id, qty] of wanted) {
      const v = vById.get(id);
      if (!v) return json({ error: "Un producto del carrito ya no está disponible" }, 409);
      const p = pById.get(v.product_id as number);
      const w = p?.wholesale_price_cents as number | null | undefined;
      // Mayoreo gana; si no, el precio lleva el descuento de oferta del producto.
      const unit = wholesaleActive && w != null
        ? w
        : offer(v.price_cents as number, p?.discount_kind, p?.discount_value);
      totalCents += unit * qty;
      items.push({
        id: String(id),
        title: String(p?.name ?? "Producto").slice(0, 250),
        quantity: qty,
        unit_price: Math.round(unit) / 100,
        currency_id: "MXN",
      });
    }
    if (totalCents <= 0) return json({ error: "Total inválido" }, 400);

    const payer = (form.payer ?? {}) as Record<string, unknown>;
    const c = (body.customer ?? {}) as Record<string, unknown>;
    const email = String((payer.email ?? c.email ?? "")).trim();
    if (!email) return json({ error: "Falta el correo del pagador" }, 400);

    // Subtotal de PRODUCTOS (antes de cupón y envío). El cupón descuenta sobre
    // esto; el umbral de envío gratis también se mide sobre esto.
    const productCents = totalCents;

    // Cupón de descuento: se valida contra la tabla `coupons` en el SERVIDOR
    // (nunca se confía en el navegador). Aplica al subtotal de productos.
    let couponDiscount = 0;
    let couponCode = "";
    const rawCoupon = String(body.coupon ?? "").trim();
    if (rawCoupon) {
      const code = rawCoupon.toUpperCase();
      const { data: cp } = await supabase
        .from("coupons")
        .select("kind, value")
        .eq("code", code)
        .eq("active", true)
        .maybeSingle();
      if (cp) {
        const val = Number(cp.value) || 0;
        couponDiscount = cp.kind === "percent"
          ? Math.round(productCents * val / 100)
          : Math.min(val, productCents);
        couponDiscount = Math.max(0, Math.min(couponDiscount, productCents));
        if (couponDiscount > 0) {
          couponCode = code;
          totalCents -= couponDiscount;
        }
      }
    }

    // Envío a domicilio: costo fijo publicado (business_card.shippingCents), con
    // envío gratis desde un umbral (freeShippingCents) sobre el total de
    // PRODUCTOS. Se lee y se suma en el SERVIDOR para que el cliente no lo evada.
    if (c.delivery) {
      const { data: card } = await supabase
        .from("business_card")
        .select("data")
        .eq("id", 1)
        .maybeSingle();
      const cardData = (card?.data ?? {}) as Record<string, unknown>;
      const fee = Number(cardData.shippingCents) || 0;
      const freeFrom = Number(cardData.freeShippingCents) || 0;
      const freeEarned = freeFrom > 0 && productCents >= freeFrom;
      if (fee > 0 && !freeEarned) {
        items.push({
          id: "shipping",
          title: "Envío a domicilio",
          quantity: 1,
          unit_price: Math.round(fee) / 100,
          currency_id: "MXN",
        });
        totalCents += fee;
      }
    }
    if (totalCents <= 0) return json({ error: "Total inválido" }, 400);

    // Nota con el cupón aplicado, para que el POS lo vea en el pedido.
    const orderNotes = [
      c.notes ? String(c.notes) : "",
      couponCode
        ? `Cupón ${couponCode} (−${(couponDiscount / 100).toFixed(2)})`
        : "",
    ].filter((s) => s).join(" · ") || null;

    // -----------------------------------------------------------------------
    // 2) Pedido pendiente (el webhook y esta misma función lo actualizan).
    // -----------------------------------------------------------------------
    const orderRow: Record<string, unknown> = {
      status: "pending",
      total_cents: totalCents,
      customer_name: c.name ?? null,
      customer_phone: c.phone ?? null,
      customer_email: email,
      delivery: !!c.delivery,
      address: c.addr ?? c.address ?? null,
      notes: orderNotes,
      items,
    };
    let order: { id: string } | null = null;
    {
      const { data, error } = await supabase
        .from("web_orders")
        .insert(orderRow)
        .select("id")
        .single();
      if (error) {
        // Si la columna customer_email no existe (migración 0010 sin aplicar),
        // reintenta sin ella en vez de tumbar el cobro.
        if (/customer_email/.test(error.message)) {
          delete orderRow.customer_email;
          const retry = await supabase
            .from("web_orders")
            .insert(orderRow)
            .select("id")
            .single();
          if (retry.error) {
            return json({ error: "No se pudo crear el pedido: " + retry.error.message }, 500);
          }
          order = retry.data as { id: string };
        } else {
          return json({ error: "No se pudo crear el pedido: " + error.message }, 500);
        }
      } else {
        order = data as { id: string };
      }
    }

    // -----------------------------------------------------------------------
    // 3) Crear el pago real en Mercado Pago con el token del Brick.
    // -----------------------------------------------------------------------
    const identification = (payer.identification ?? undefined) as
      | Record<string, unknown>
      | undefined;
    // Datos del pagador para el motor antifraude: nombre, apellido y teléfono.
    // Mientras más señales, menos rechazos por "riesgo alto".
    const fullName = String(c.name ?? "").trim();
    const firstName = fullName.split(/\s+/)[0] || undefined;
    const lastName = fullName.split(/\s+/).slice(1).join(" ") || undefined;
    const phoneDigits = String(c.phone ?? "").replace(/\D/g, "");
    const phone = phoneDigits.length >= 10
      ? { area_code: phoneDigits.slice(0, 3), number: phoneDigits.slice(3) }
      : undefined;
    // Dirección estructurada del comprador: otra señal fuerte para el antifraude.
    const zip = String(c.zip ?? "").replace(/\D/g, "");
    const street = String(c.street ?? "").trim();
    const colonia = String(c.colonia ?? "").trim();
    const city = String(c.city ?? "").trim();
    const state = String(c.state ?? "").trim();
    const address = zip || street
      ? {
          ...(zip ? { zip_code: zip } : {}),
          ...(street ? { street_name: street } : {}),
          ...(colonia ? { neighborhood: colonia } : {}),
          ...(city ? { city } : {}),
          ...(state ? { federal_unit: state } : {}),
        }
      : undefined;
    const payerBlock: Record<string, unknown> = {
      email,
      ...(firstName ? { first_name: firstName } : {}),
      ...(lastName ? { last_name: lastName } : {}),
      ...(phone ? { phone } : {}),
      ...(address ? { address } : {}),
      ...(identification && identification.number ? { identification } : {}),
    };
    const payBody: Record<string, unknown> = {
      transaction_amount: Math.round(totalCents) / 100,
      token: form.token,
      description: `Pedido ${order!.id}`,
      installments: Number(form.installments) || 1,
      payment_method_id: form.payment_method_id,
      external_reference: order!.id,
      notification_url: `${Deno.env.get("SUPABASE_URL")}/functions/v1/mp-webhook`,
      metadata: { order_id: order!.id },
      payer: payerBlock,
      additional_info: {
        items: items.map((it) => ({
          id: it.id,
          title: it.title,
          quantity: it.quantity,
          unit_price: it.unit_price,
        })),
        payer: {
          ...(firstName ? { first_name: firstName } : {}),
          ...(lastName ? { last_name: lastName } : {}),
          ...(phone ? { phone } : {}),
          ...(address
            ? { address: { zip_code: zip, street_name: street } }
            : {}),
        },
        ...(c.delivery && address
          ? {
              shipments: {
                receiver_address: {
                  zip_code: zip,
                  street_name: street,
                  city_name: city,
                  state_name: state,
                },
              },
            }
          : {}),
      },
    };
    if (form.issuer_id) payBody.issuer_id = form.issuer_id;

    // Huella del dispositivo (device fingerprint): es la señal antifraude más
    // importante en checkout transparente. Sin ella MP suele rechazar como
    // "cc_rejected_high_risk". La manda el frontend (window.MP_DEVICE_SESSION_ID)
    // y va en el header X-meli-session-id.
    const deviceId = String(body.device_id ?? "").trim();

    const payRes = await fetch("https://api.mercadopago.com/v1/payments", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${MP_TOKEN}`,
        "Content-Type": "application/json",
        // Una llave por pedido: un reintento sobre el MISMO pedido no cobra dos
        // veces (cada envío del Brick crea un pedido nuevo, así que es único).
        "X-Idempotency-Key": order!.id,
        // Huella del dispositivo para el antifraude de MP (reduce high_risk).
        ...(deviceId ? { "X-meli-session-id": deviceId } : {}),
      },
      body: JSON.stringify(payBody),
    });
    const pay = await payRes.json().catch(() => ({}));

    if (!payRes.ok) {
      await supabase
        .from("web_orders")
        .update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("id", order!.id);
      return json(
        {
          error: "Mercado Pago: " + (pay.message ?? pay.error ?? payRes.status),
          status: "error",
          order_id: order!.id,
        },
        502,
      );
    }

    const dbStatus =
      pay.status === "approved" ? "paid"
      : pay.status === "rejected" ? "failed"
      : pay.status === "cancelled" ? "cancelled"
      : "pending";

    await supabase
      .from("web_orders")
      .update({
        status: dbStatus,
        mp_payment_id: String(pay.id ?? ""),
        updated_at: new Date().toISOString(),
      })
      .eq("id", order!.id);

    // Correos de confirmación (best-effort: nunca afectan la respuesta del pago).
    if (dbStatus === "paid" || dbStatus === "pending") {
      try {
        await sendConfirmationEmails({
          toCustomer: email,
          orderId: order!.id,
          items,
          totalCents,
          customer: {
            name: String(c.name ?? ""),
            phone: phoneDigits,
            email,
            addr: String(c.addr ?? c.address ?? ""),
            delivery: !!c.delivery,
          },
          approved: dbStatus === "paid",
        });
      } catch (_) { /* el correo nunca debe tumbar el cobro */ }
    }

    return json({
      status: pay.status, // approved | in_process | rejected | ...
      status_detail: pay.status_detail,
      order_id: order!.id,
      payment_id: pay.id,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
