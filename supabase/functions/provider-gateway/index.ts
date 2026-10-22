import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "POST required" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return reply({ error: "Supabase function environment is not configured." }, 500);

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) return reply({ error: "SUPABASE_SERVICE_ROLE_KEY is not configured in Edge Function secrets." }, 500);
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return reply({ error: "Sign in to use provider services." }, 401);
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return reply({ error: "A valid signed-in user is required." }, 401);

  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return reply({ error: "Invalid JSON body." }, 400);
  }

  const action = String(input.action ?? "");
  try {

    if (action === "credit-purchase-initialize") {
      const email = String(input.email ?? "").trim();
      const credits = Number(input.credits);
      const packages: Record<number, number> = { 100: 1332, 250: 3330, 500: 6659, 1000: 13318, 2500: 33295, 5000: 66590, 10000: 133180 };
      const amount = packages[credits];
      if (!email || !amount) return reply({ error: "Choose a valid credit package." }, 400);
      const txRef = `NOVARYX-${userData.user.id}-${crypto.randomUUID()}`;
      const { error: insertError } = await admin.from("credit_purchases").insert({ tx_ref: txRef, user_id: userData.user.id, credits, amount_ngn: amount, status: "pending" });
      if (insertError) return reply({ error: "Could not create purchase record: " + insertError.message }, 500);
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const redirectUrl = String(input.redirect_url ?? "");
      const upstream = await fetch("https://api.flutterwave.com/v3/payments", {
        method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ tx_ref: txRef, amount, currency: "NGN", redirect_url: redirectUrl, customer: { email, name: String(input.name ?? "") }, customizations: { title: "NOVARYX-AI", description: `${credits} generation credits` } })
      });
      const result = await upstream.json();
      const checkoutUrl = result?.data?.link;
      if (!upstream.ok || typeof checkoutUrl !== "string") {
        await admin.from("credit_purchases").update({ status: "failed" }).eq("tx_ref", txRef);
        return reply({ error: result?.message ?? "Flutterwave could not start checkout." }, upstream.status || 502);
      }
      return reply({ checkout_url: checkoutUrl, tx_ref: txRef, credits, amount_ngn: amount });
    }

    if (action === "credit-purchase-verify") {
      const txRef = String(input.tx_ref ?? "");
      const transactionId = String(input.transaction_id ?? "");
      if (!txRef || !/^\\d+$/.test(transactionId)) return reply({ error: "Purchase reference and numeric Flutterwave transaction ID are required." }, 400);
      const { data: purchase, error: purchaseError } = await admin.from("credit_purchases").select("*").eq("tx_ref", txRef).eq("user_id", userData.user.id).maybeSingle();
      if (purchaseError || !purchase) return reply({ error: "Purchase not found for this account." }, 404);
      if (purchase.status === "fulfilled") {
        const { data: fulfilled } = await admin.rpc("fulfill_credit_purchase", { p_tx_ref: txRef });
        return reply(fulfilled ?? { credits_added: purchase.credits, already_fulfilled: true });
      }
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const verifyResponse = await fetch(`https://api.flutterwave.com/v3/transactions/${transactionId}/verify`, { headers: { Authorization: `Bearer ${key}` } });
      const verification = await verifyResponse.json();
      const payment = verification?.data;
      if (!verifyResponse.ok || verification?.status !== "success" || payment?.status !== "successful" ||
          String(payment?.tx_ref) !== txRef || Number(payment?.amount) < Number(purchase.amount_ngn) ||
          String(payment?.currency) !== "NGN") {
        return reply({ error: "Flutterwave could not confirm a matching successful payment. Check the transaction ID and try again." }, 402);
      }
      const { error: markError } = await admin.from("credit_purchases").update({ status: "verified", flutterwave_transaction_id: transactionId }).eq("tx_ref", txRef).eq("user_id", userData.user.id).neq("status", "fulfilled");
      if (markError) return reply({ error: "Payment verified but credit fulfilment could not be prepared: " + markError.message }, 500);
      const { data: fulfilled, error: fulfilError } = await admin.rpc("fulfill_credit_purchase", { p_tx_ref: txRef });
      if (fulfilError) return reply({ error: "Payment verified, but credit fulfilment failed. Contact support with reference " + txRef }, 500);
      return reply(fulfilled);
    }

    if (action === "chat") {
      const key = Deno.env.get("GROQ_API_KEY");
      if (!key) return reply({ error: "GROQ_API_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const messages = input.messages;
      if (!Array.isArray(messages) || messages.length === 0) return reply({ error: "messages must be a non-empty array." }, 400);
      const { error: creditError } = await supabase.rpc("spend_generation_credits", { p_amount: 1 });
      if (creditError) return reply({ error: creditError.message.includes("Not enough") ? "Not enough generation credits. Check your balance or purchase more credits." : creditError.message }, 402);
      const upstream = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: String(input.model ?? "llama-3.3-70b-versatile"),
          messages,
          temperature: 0.7,
        }),
      });
      return reply(await upstream.json(), upstream.status);
    }

    if (action === "kie-create") {
      const key = Deno.env.get("KIE_API_KEY");
      if (!key) return reply({ error: "KIE_API_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const model = String(input.model ?? "");
      const prompt = String(input.prompt ?? "").trim();
      if (!model || !prompt) return reply({ error: "model and prompt are required." }, 400);
      const generationKind = String(input.generationKind ?? "");
      const costs: Record<string, number> = { image: 3, music: 5, video: 8 };
      const cost = costs[generationKind];
      if (!cost) return reply({ error: "generationKind must be image, music, or video." }, 400);
      const { error: creditError } = await supabase.rpc("spend_generation_credits", { p_amount: cost });
      if (creditError) return reply({ error: creditError.message.includes("Not enough") ? "Not enough generation credits. Check your balance or purchase more credits." : creditError.message }, 402);
      const upstream = await fetch("https://api.kie.ai/api/v1/jobs/createTask", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, input: { prompt, ...(generationKind !== "music" && typeof input.aspectRatio === "string" ? { aspect_ratio: input.aspectRatio } : {}), ...(generationKind !== "music" && typeof input.imageUrl === "string" && input.imageUrl.trim() ? { image_url: input.imageUrl.trim() } : {}), ...(generationKind === "video" && typeof input.videoUrl === "string" && input.videoUrl.trim() ? { video_url: input.videoUrl.trim() } : {}) } }),
      });
      return reply(await upstream.json(), upstream.status);
    }

    if (action === "kie-poll") {
      const key = Deno.env.get("KIE_API_KEY");
      if (!key) return reply({ error: "KIE_API_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const taskId = String(input.taskId ?? "");
      if (!taskId) return reply({ error: "taskId is required." }, 400);
      const upstream = await fetch(`https://api.kie.ai/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`, {
        headers: { Authorization: `Bearer ${key}` },
      });
      return reply(await upstream.json(), upstream.status);
    }

    if (action === "flutterwave-initialize") {
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const email = String(input.email ?? "").trim();
      const amount = Number(input.amount);
      const txRef = String(input.tx_ref ?? crypto.randomUUID());
      const currency = String(input.currency ?? "NGN");
      const redirectUrl = String(input.redirect_url ?? "");
      if (!email || !Number.isFinite(amount) || amount <= 0 || !redirectUrl) {
        return reply({ error: "email, positive amount, and redirect_url are required." }, 400);
      }
      const upstream = await fetch("https://api.flutterwave.com/v3/payments", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          tx_ref: txRef, amount, currency, redirect_url: redirectUrl,
          customer: { email, name: String(input.name ?? "") },
          customizations: { title: "NOVARYX-AI", description: "NOVARYX-AI payment" },
        }),
      });
      return reply(await upstream.json(), upstream.status);
    }

    if (action === "flutterwave-verify") {
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const transactionId = String(input.transaction_id ?? "");
      if (!/^\d+$/.test(transactionId)) return reply({ error: "A numeric transaction_id is required." }, 400);
      const upstream = await fetch(`https://api.flutterwave.com/v3/transactions/${transactionId}/verify`, {
        headers: { Authorization: `Bearer ${key}` },
      });
      return reply(await upstream.json(), upstream.status);
    }

    return reply({ error: "Unknown action. Use credit-purchase-initialize, credit-purchase-verify, chat, kie-create, or kie-poll." }, 400);
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : "Provider request failed." }, 502);
  }
});
