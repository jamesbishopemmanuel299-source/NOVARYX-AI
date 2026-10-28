const http = require("node:http");

const PORT = Number(process.env.PORT || 10000);
const SUPABASE_URL = String(process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const SUPABASE_PUBLISHABLE_KEY = String(
  process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ""
).trim();

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type, accept, x-client-info",
  });
  res.end(payload);
}

function isValidSupabaseConfig() {
  try {
    const url = new URL(SUPABASE_URL);
    return url.protocol === "https:" &&
      url.hostname.endsWith(".supabase.co") &&
      Boolean(SUPABASE_PUBLISHABLE_KEY);
  } catch {
    return false;
  }
}

async function readJson(req, limitBytes = 2 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limitBytes) {
      const error = new Error("Request body is too large.");
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  try {
    return JSON.parse(raw || "{}");
  } catch {
    const error = new Error("Request body must be valid JSON.");
    error.statusCode = 400;
    throw error;
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", "http://localhost");

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers": "authorization, apikey, content-type, accept, x-client-info",
      "access-control-max-age": "86400",
    });
    return res.end();
  }

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
    return sendJson(res, 200, {
      name: "NOVARYX-AI API",
      status: "online",
      configured: isValidSupabaseConfig(),
    });
  }

  if (req.method === "GET" && url.pathname === "/api/config") {
    if (!isValidSupabaseConfig()) {
      return sendJson(res, 503, {
        error: "Render is missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY.",
      });
    }
    // Only public client configuration is returned. Never expose service-role,
    // Groq, Kie.ai, or Flutterwave secret keys from this endpoint.
    return sendJson(res, 200, {
      supabaseUrl: SUPABASE_URL,
      supabasePublishableKey: SUPABASE_PUBLISHABLE_KEY,
    });
  }

  if (req.method === "POST" && url.pathname === "/api/provider-gateway") {
    if (!isValidSupabaseConfig()) {
      return sendJson(res, 503, { error: "Render API configuration is incomplete." });
    }

    const authorization = String(req.headers.authorization || "").trim();
    if (!/^Bearer\s+\S+$/i.test(authorization)) {
      return sendJson(res, 401, { error: "Sign in before using NOVARYX-AI provider services." });
    }

    try {
      const body = await readJson(req);
      const upstream = await fetch(`${SUPABASE_URL}/functions/v1/provider-gateway`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "accept": "application/json",
          "apikey": SUPABASE_PUBLISHABLE_KEY,
          "authorization": authorization,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(120000),
      });
      const responseText = await upstream.text();
      res.writeHead(upstream.status, {
        "content-type": upstream.headers.get("content-type") || "application/json; charset=utf-8",
        "cache-control": "no-store",
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, apikey, content-type, accept, x-client-info",
      });
      return res.end(responseText);
    } catch (error) {
      const status = Number(error && error.statusCode) || 502;
      return sendJson(res, status, {
        error: status === 502
          ? "Could not reach the provider gateway. Check Render and Supabase Edge Function status."
          : String(error.message || "Request failed."),
      });
    }
  }

  return sendJson(res, 404, { error: "Route not found." });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`NOVARYX-AI Render API listening on port ${PORT}`);
});
