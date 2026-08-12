// Edge Function: webhook de Mercado Pago. MP la llama cuando cambia un pago.
//
// Consulta el pago real a MP (fuente de la verdad, no se confía en el aviso) y
// actualiza el pedido en `web_orders` (paid / failed / cancelled). Siempre
// responde 200 para que MP no reintente en bucle por un error nuestro.
//
// Secreto: MP_ACCESS_TOKEN. Inyectados: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Nota: esta función debe desplegarse SIN verificación de JWT
//   supabase functions deploy mp-webhook --no-verify-jwt
// porque MP la llama sin la llave de Supabase.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    const MP_TOKEN = Deno.env.get("MP_ACCESS_TOKEN");
    if (!MP_TOKEN) return new Response("sin token", { status: 200 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // MP manda el aviso por query (?type=payment&data.id=...) o en el cuerpo.
    const url = new URL(req.url);
    let paymentId =
      url.searchParams.get("data.id") ?? url.searchParams.get("id");
    let topic = url.searchParams.get("type") ?? url.searchParams.get("topic");
    if (!paymentId) {
      const b = await req.json().catch(() => ({} as Record<string, unknown>));
      const data = (b as { data?: { id?: unknown }; type?: unknown });
      paymentId = data?.data?.id ? String(data.data.id) : null;
      topic = (data?.type as string) ?? topic;
    }

    if (topic && topic !== "payment") return new Response("ignorado", { status: 200 });
    if (!paymentId) return new Response("sin id", { status: 200 });

    // Consultar el pago real a MP.
    const payRes = await fetch(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      { headers: { Authorization: `Bearer ${MP_TOKEN}` } },
    );
    if (!payRes.ok) return new Response("pago no encontrado", { status: 200 });
    const pay = await payRes.json();

    const orderId = pay.external_reference;
    if (!orderId) return new Response("sin referencia", { status: 200 });

    const status =
      pay.status === "approved" ? "paid"
      : pay.status === "rejected" ? "failed"
      : pay.status === "cancelled" ? "cancelled"
      : "pending";

    await supabase
      .from("web_orders")
      .update({
        status,
        mp_payment_id: String(paymentId),
        updated_at: new Date().toISOString(),
      })
      .eq("id", orderId);

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response("error: " + e, { status: 200 });
  }
});
