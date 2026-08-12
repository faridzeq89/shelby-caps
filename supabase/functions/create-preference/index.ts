// Edge Function: crea una preferencia de pago en Mercado Pago (Checkout Pro).
//
// La llama la tienda (con la llave anon) al tocar "Pagar con Mercado Pago".
// El monto se RECALCULA aquí en el servidor (no se confía en el cliente), se
// guarda un pedido en `web_orders` (status=pending) y se devuelve el `init_point`
// al que la tienda redirige. El webhook `mp-webhook` confirma el pago después.
//
// Secretos que necesita (se ponen con `supabase secrets set`, NO van en el repo):
//   MP_ACCESS_TOKEN   -> Access Token de Mercado Pago (TEST-... en sandbox)
// Ya vienen inyectados por Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

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
    const rawItems = Array.isArray(body.items) ? body.items : [];
    if (rawItems.length === 0) return json({ error: "El carrito está vacío" }, 400);

    // Recalcular el total en el servidor. `unit_price` viene en PESOS (2 dec).
    let totalCents = 0;
    const items = rawItems.map((it: Record<string, unknown>) => {
      const quantity = Math.max(1, parseInt(String(it.quantity)) || 1);
      const unitPrice = Math.max(0, Math.round(Number(it.unit_price) * 100) / 100);
      totalCents += Math.round(unitPrice * 100) * quantity;
      return {
        title: String(it.title ?? "Producto").slice(0, 250),
        quantity,
        unit_price: unitPrice,
        currency_id: "MXN",
      };
    });
    if (totalCents <= 0) return json({ error: "Total inválido" }, 400);

    const c = (body.customer ?? {}) as Record<string, unknown>;
    const storeUrl = String(body.store_url || "https://shelby-caps.pages.dev");

    // 1) Guardar el pedido pendiente.
    const { data: order, error } = await supabase
      .from("web_orders")
      .insert({
        status: "pending",
        total_cents: totalCents,
        customer_name: c.name ?? null,
        customer_phone: c.phone ?? null,
        delivery: !!c.delivery,
        address: c.address ?? null,
        notes: c.notes ?? null,
        items,
      })
      .select("id")
      .single();
    if (error) return json({ error: "No se pudo crear el pedido: " + error.message }, 500);

    // 2) Crear la preferencia en Mercado Pago.
    const prefRes = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${MP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        items,
        external_reference: order.id,
        back_urls: {
          success: `${storeUrl}?pago=exito`,
          failure: `${storeUrl}?pago=error`,
          pending: `${storeUrl}?pago=pendiente`,
        },
        auto_return: "approved",
        notification_url: `${Deno.env.get("SUPABASE_URL")}/functions/v1/mp-webhook`,
        statement_descriptor: "SHELBYCAPS",
        metadata: { order_id: order.id },
      }),
    });
    const pref = await prefRes.json();
    if (!prefRes.ok) {
      return json({ error: "Mercado Pago: " + (pref.message ?? prefRes.status) }, 502);
    }

    await supabase
      .from("web_orders")
      .update({ mp_preference_id: pref.id })
      .eq("id", order.id);

    // `init_point` = checkout real; `sandbox_init_point` = pruebas.
    return json({
      order_id: order.id,
      init_point: pref.init_point,
      sandbox_init_point: pref.sandbox_init_point,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
