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

// Return provider diagnostics without ever returning request headers or secret values.
function flutterwaveDiagnostic(stage: string, response: Response, payload: any, extra: Record<string, unknown> = {}) {
  const providerStatus = String(payload?.status ?? "unknown");
  const providerCode = payload?.code ?? payload?.data?.code ?? null;
  const providerMessage = String(payload?.message ?? payload?.data?.message ?? "No provider message returned.");
  const requestId = response.headers.get("x-request-id") ??
    response.headers.get("request-id") ??
    response.headers.get("flutterwave-request-id") ?? null;
  const detail = [
    "Flutterwave " + stage + " failed.",
    "HTTP status: " + response.status,
    "Provider status: " + providerStatus,
    "Provider code: " + (providerCode ?? "not supplied"),
    "Provider message: " + providerMessage,
    requestId ? "Request ID: " + requestId : "Request ID: not supplied",
    ...Object.entries(extra).map(([key, value]) => key + ": " + String(value)),
  ].join("\\n");
  return {
    error: detail,
    diagnostic: {
      provider: "Flutterwave",
      stage,
      http_status: response.status,
      provider_status: providerStatus,
      provider_code: providerCode,
      provider_message: providerMessage,
      request_id: requestId,
      ...extra,
    },
  };
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
    if (action === "provider-status") {
      return reply({
        kie: Boolean(Deno.env.get("KIE_API_KEY")),
        flutterwave: Boolean(Deno.env.get("FLUTTERWAVE_SECRET_KEY") && Deno.env.get("FLUTTERWAVE_REDIRECT_URL")),
        flutterwave_secret_configured: Boolean(Deno.env.get("FLUTTERWAVE_SECRET_KEY")),
        flutterwave_redirect_configured: Boolean(Deno.env.get("FLUTTERWAVE_REDIRECT_URL")),
        supabase: Boolean(supabaseUrl && anonKey && serviceRoleKey),
      });
    }

    if (action === "credit-purchase-initialize") {
      const email = String(input.email ?? "").trim();
      const credits = Number(input.credits);
      const packages: Record<number, number> = { 100: 1332, 250: 3330, 500: 6659, 1000: 13318, 2500: 33295, 5000: 66590, 10000: 133180 };
      const amount = packages[credits];
      if (!email || !amount) return reply({ error: "Choose a valid credit package." }, 400);
      if (!Deno.env.get("FLUTTERWAVE_REDIRECT_URL")) return reply({ error: "FLUTTERWAVE_REDIRECT_URL is missing in Supabase Edge Function secrets. Add a valid HTTPS payment return URL." }, 500);
      const txRef = `NOVARYX-${userData.user.id}-${crypto.randomUUID()}`;
      const { error: insertError } = await admin.from("credit_purchases").insert({ tx_ref: txRef, user_id: userData.user.id, credits, amount_ngn: amount, status: "pending" });
      if (insertError) return reply({ error: "Could not create purchase record: " + insertError.message, stage: "database_purchase_record", tx_ref: txRef }, 500);
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is missing in Supabase Edge Function secrets. The secret value is never displayed." , stage: "configuration", tx_ref: txRef }, 500);
      const redirectUrl = Deno.env.get("FLUTTERWAVE_REDIRECT_URL") ?? "";
      const upstream = await fetch("https://api.flutterwave.com/v3/payments", {
        method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ tx_ref: txRef, amount, currency: "NGN", redirect_url: redirectUrl, customer: { email, name: String(input.name ?? "") }, customizations: { title: "NOVARYX-AI", description: `${credits} generation credits` } })
      });
      const result = await upstream.json().catch(() => ({}));
      const checkoutUrl = result?.data?.link;
      if (!upstream.ok || typeof checkoutUrl !== "string") {
        await admin.from("credit_purchases").update({ status: "failed" }).eq("tx_ref", txRef);
        return reply({ ...flutterwaveDiagnostic("checkout initialization", upstream, result, { transaction_reference: txRef, amount_ngn: amount, currency: "NGN" }), tx_ref: txRef }, upstream.status || 502);
      }
      return reply({ checkout_url: checkoutUrl, tx_ref: txRef, credits, amount_ngn: amount });
    }

    if (action === "credit-purchase-verify") {
      const txRef = String(input.tx_ref ?? "");
      const transactionId = String(input.transaction_id ?? "");
      if (!txRef || !/^\d+$/.test(transactionId)) return reply({ error: "Purchase reference and numeric Flutterwave transaction ID are required." }, 400);
      const { data: purchase, error: purchaseError } = await admin.from("credit_purchases").select("*").eq("tx_ref", txRef).eq("user_id", userData.user.id).maybeSingle();
      if (purchaseError || !purchase) return reply({ error: "Purchase not found for this account.", detail: purchaseError?.message ?? null, tx_ref: txRef }, 404);
      if (purchase.status === "fulfilled") {
        const { data: fulfilled } = await admin.rpc("fulfill_credit_purchase", { p_tx_ref: txRef });
        return reply(fulfilled ?? { credits_added: purchase.credits, already_fulfilled: true });
      }
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is missing in Supabase Edge Function secrets. The secret value is never displayed.", stage: "configuration", tx_ref: txRef }, 500);
      const verifyResponse = await fetch(`https://api.flutterwave.com/v3/transactions/${transactionId}/verify`, { headers: { Authorization: `Bearer ${key}` } });
      const verification = await verifyResponse.json().catch(() => ({}));
      const payment = verification?.data;
      const matches = verifyResponse.ok && verification?.status === "success" && payment?.status === "successful" &&
        String(payment?.tx_ref) === txRef && Number(payment?.amount) >= Number(purchase.amount_ngn) &&
        String(payment?.currency) === "NGN";
      if (!matches) {
        const diagnostic = flutterwaveDiagnostic("transaction verification", verifyResponse, verification, {
          transaction_reference_expected: txRef,
          transaction_reference_returned: payment?.tx_ref ?? "not supplied",
          payment_status: payment?.status ?? "not supplied",
          amount_expected_ngn: purchase.amount_ngn,
          amount_returned: payment?.amount ?? "not supplied",
          currency_expected: "NGN",
          currency_returned: payment?.currency ?? "not supplied",
          transaction_id: transactionId,
        });
        return reply(diagnostic, verifyResponse.ok ? 402 : (verifyResponse.status || 502));
      }
      const { error: markError } = await admin.from("credit_purchases").update({ status: "verified", flutterwave_transaction_id: transactionId }).eq("tx_ref", txRef).eq("user_id", userData.user.id).neq("status", "fulfilled");
      if (markError) return reply({ error: "Flutterwave confirmed payment, but the database could not prepare credit fulfilment.", detail: markError.message, tx_ref: txRef, transaction_id: transactionId }, 500);
      const { data: fulfilled, error: fulfilError } = await admin.rpc("fulfill_credit_purchase", { p_tx_ref: txRef });
      if (fulfilError) return reply({ error: "Flutterwave confirmed payment, but credit fulfilment failed.", detail: fulfilError.message, tx_ref: txRef, transaction_id: transactionId }, 500);
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
        body: JSON.stringify({ model: String(input.model ?? "llama-3.3-70b-versatile"), messages, temperature: 0.7 }),
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
      if (!["image", "music", "video"].includes(generationKind)) return reply({ error: "generationKind must be image, music, or video." }, 400);
      const { data: creditRow, error: balanceError } = await admin.from("generation_credits").select("balance").eq("user_id", userData.user.id).maybeSingle();
      if (balanceError) return reply({ error: "Could not check your credit balance: " + balanceError.message }, 500);
      if (!creditRow || Number(creditRow.balance) <= 0) return reply({ error: "You need available credits before starting a generation. Top up your balance to continue." }, 402);
      const upstream = await fetch("https://api.kie.ai/api/v1/jobs/createTask", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, input: { prompt, ...(generationKind !== "music" && typeof input.aspectRatio === "string" ? { aspect_ratio: input.aspectRatio } : {}), ...(generationKind !== "music" && typeof input.imageUrl === "string" && input.imageUrl.trim() ? { image_url: input.imageUrl.trim() } : {}), ...(generationKind === "video" && typeof input.videoUrl === "string" && input.videoUrl.trim() ? { video_url: input.videoUrl.trim() } : {}) } }),
      });
      const result = await upstream.json();
      if (!upstream.ok || (result?.code !== undefined && Number(result.code) !== 200)) return reply({ error: result?.msg || result?.message || "KIE could not accept this generation task.", provider: result }, upstream.status || 502);
      const taskId = String(result?.data?.taskId ?? result?.data?.task_id ?? result?.taskId ?? "");
      if (!taskId) return reply({ error: "KIE did not return a task ID, so no credits were deducted.", provider: result }, 502);
      const { error: billingInsertError } = await admin.from("kie_task_billing").insert({ task_id: taskId, user_id: userData.user.id, generation_kind: generationKind, model, status: "pending" });
      if (billingInsertError) return reply({ error: "KIE accepted the task but its billing record could not be saved. Contact support with task ID " + taskId }, 500);
      return reply(result, upstream.status);
    }

    if (action === "kie-poll") {
      const key = Deno.env.get("KIE_API_KEY");
      if (!key) return reply({ error: "KIE_API_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const taskId = String(input.taskId ?? "");
      if (!taskId) return reply({ error: "taskId is required." }, 400);
      const { data: billingRow, error: billingLookupError } = await admin.from("kie_task_billing").select("task_id,user_id,status,credits_consumed").eq("task_id", taskId).eq("user_id", userData.user.id).maybeSingle();
      if (billingLookupError) return reply({ error: "Could not verify task ownership: " + billingLookupError.message }, 500);
      if (!billingRow) return reply({ error: "This generation task does not belong to your account." }, 404);
      const upstream = await fetch(`https://api.kie.ai/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`, { headers: { Authorization: `Bearer ${key}` } });
      const result = await upstream.json();
      if (!upstream.ok || (result?.code !== undefined && Number(result.code) !== 200)) return reply(result, upstream.status);
      const task = result?.data ?? result;
      const state = String(task?.state ?? task?.status ?? "").toLowerCase();
      if (["fail", "failed", "error", "cancelled", "canceled"].includes(state)) {
        if (billingRow.status === "pending") await admin.from("kie_task_billing").update({ status: "failed" }).eq("task_id", taskId).eq("user_id", userData.user.id).eq("status", "pending");
        return reply({ ...result, billing: { status: "failed", credits_consumed: 0, message: "KIE failed this task; no generation credits were charged." } }, upstream.status);
      }
      if (["success", "completed", "succeed"].includes(state) && billingRow.status !== "settled") {
        const consumed = Number(task?.creditsConsumed ?? task?.credits_consumed);
        if (!Number.isSafeInteger(consumed) || consumed < 0) return reply({ ...result, billing: { status: "pending", message: "Waiting for KIE to report the exact creditsConsumed value." } }, upstream.status);
        const { data: settlement, error: settlementError } = await admin.rpc("settle_kie_task_credits", { p_task_id: taskId, p_credits: consumed });
        if (settlementError) return reply({ error: "Generation succeeded, but exact credit settlement failed. Contact support with task ID " + taskId, detail: settlementError.message }, 500);
        return reply({ ...result, billing: { status: "settled", ...settlement } }, upstream.status);
      }
      if (billingRow.status === "settled") return reply({ ...result, billing: { status: "settled", credits_consumed: billingRow.credits_consumed } }, upstream.status);
      return reply({ ...result, billing: { status: "pending", message: "No credits are charged until KIE reports a successful task and its exact cost." } }, upstream.status);
    }

    if (action === "flutterwave-initialize") {
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const email = String(input.email ?? "").trim();
      const amount = Number(input.amount);
      const txRef = String(input.tx_ref ?? crypto.randomUUID());
      const currency = String(input.currency ?? "NGN");
      const redirectUrl = String(input.redirect_url ?? "");
      if (!email || !Number.isFinite(amount) || amount <= 0 || !redirectUrl) return reply({ error: "email, positive amount, and redirect_url are required." }, 400);
      const upstream = await fetch("https://api.flutterwave.com/v3/payments", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ tx_ref: txRef, amount, currency, redirect_url: redirectUrl, customer: { email, name: String(input.name ?? "") }, customizations: { title: "NOVARYX-AI", description: "NOVARYX-AI payment" } }),
      });
      const result = await upstream.json().catch(() => ({}));
      if (!upstream.ok || typeof result?.data?.link !== "string") return reply(flutterwaveDiagnostic("checkout initialization", upstream, result, { transaction_reference: txRef, amount, currency }), upstream.status || 502);
      return reply(result, upstream.status);
    }

    if (action === "flutterwave-verify") {
      const key = Deno.env.get("FLUTTERWAVE_SECRET_KEY");
      if (!key) return reply({ error: "FLUTTERWAVE_SECRET_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const transactionId = String(input.transaction_id ?? "");
      if (!/^\d+$/.test(transactionId)) return reply({ error: "A numeric transaction_id is required." }, 400);
      const upstream = await fetch(`https://api.flutterwave.com/v3/transactions/${transactionId}/verify`, { headers: { Authorization: `Bearer ${key}` } });
      const result = await upstream.json().catch(() => ({}));
      if (!upstream.ok || result?.status !== "success") return reply(flutterwaveDiagnostic("transaction verification", upstream, result, { transaction_id: transactionId }), upstream.status || 502);
      return reply(result, upstream.status);
    }

    return reply({ error: "Unknown action. Use credit-purchase-initialize, credit-purchase-verify, chat, kie-create, or kie-poll." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Provider request failed.";
    return reply({ error: message, stage: "gateway_exception" }, 502);
  }
});