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
    if (action === "chat") {
      const key = Deno.env.get("GROQ_API_KEY");
      if (!key) return reply({ error: "GROQ_API_KEY is not configured in Supabase Edge Function secrets." }, 500);
      const messages = input.messages;
      if (!Array.isArray(messages) || messages.length === 0) return reply({ error: "messages must be a non-empty array." }, 400);
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
      const upstream = await fetch("https://api.kie.ai/api/v1/jobs/createTask", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, input: { prompt } }),
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

    return reply({ error: "Unknown action. Use chat, kie-create, kie-poll, flutterwave-initialize, or flutterwave-verify." }, 400);
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : "Provider request failed." }, 502);
  }
});
