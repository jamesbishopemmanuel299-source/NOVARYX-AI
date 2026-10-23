const http = require("node:http");

const PORT = Number(process.env.PORT || 10000);

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    return res.end();
  }

  const url = new URL(req.url, "http://localhost");

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
    return sendJson(res, 200, {
      name: "NOVARYX-AI Config API",
      status: "online",
      endpoints: ["/health", "/api/config"],
    });
  }

  if (req.method === "GET" && url.pathname === "/api/config") {
    const supabaseUrl = process.env.SUPABASE_URL;
    const publishableKey =
      process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;

    if (!supabaseUrl || !publishableKey) {
      return sendJson(res, 503, {
        error: "server_configuration_missing",
        message: "Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) in Render environment variables.",
      });
    }

    try {
      const parsed = new URL(supabaseUrl);
      if (parsed.protocol !== "https:") throw new Error("HTTPS required");
    } catch (_) {
      return sendJson(res, 500, {
        error: "invalid_server_configuration",
        message: "SUPABASE_URL must be a valid HTTPS URL.",
      });
    }

    return sendJson(res, 200, {
      supabaseUrl,
      supabasePublishableKey: publishableKey,
    });
  }

  return sendJson(res, 404, { error: "not_found", path: url.pathname });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`NOVARYX-AI Config API listening on port ${PORT}`);
});
