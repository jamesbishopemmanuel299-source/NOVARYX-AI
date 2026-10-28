const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const PORT = Number(process.env.PORT || 10000);
const SUPABASE_URL = String(process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const SUPABASE_PUBLISHABLE_KEY = String(
  process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ""
).trim();
const INDEX_FILE = path.join(__dirname, "public", "index.html");

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

  if (req.method === "GET" && url.pathname === "/") {
    if (!fs.existsSync(INDEX_FILE)) {
      return sendJson(res, 500, { error: "Website interface file is missing from the deployment." });
    }
    const html = fs.readFileSync(INDEX_FILE, "utf8");
    const chatUi = \`
<style id="novaryx-chatgpt-refresh">
:root{color-scheme:dark;--chat-bg:#212121;--chat-side:#171717;--chat-panel:#2f2f2f;--chat-line:#414141;--chat-text:#f4f4f4;--chat-muted:#aaa}
body{background:var(--chat-bg)!important;color:var(--chat-text)!important}body:before{display:none!important}
.top{background:rgba(33,33,33,.94);border:0;position:sticky;top:0;z-index:20;padding:12px 20px!important;backdrop-filter:blur(16px)}
.wrap{width:100%!important;max-width:none!important}.brand{letter-spacing:.02em!important}.logo{background:linear-gradient(135deg,#3979ff,#58d7f5)!important;box-shadow:none!important}.tag{display:none!important}
.app{grid-template-columns:255px minmax(0,1fr)!important;gap:0!important;padding:0!important;min-height:calc(100vh - 65px)}
.side{position:sticky!important;top:65px!important;height:calc(100vh - 65px)!important;overflow:auto!important;background:var(--chat-side)!important;border:0!important;border-right:1px solid #303030!important;border-radius:0!important;padding:14px 10px!important;box-shadow:none!important}
.side .nav{color:#d1d1d1!important;border:1px solid transparent!important;border-radius:10px!important;padding:11px 12px!important;margin:3px 0!important}.side .nav.active,.side .nav:hover{background:#2d2d2d!important;border-color:#3b3b3b!important;color:white!important;box-shadow:none!important}
.main{padding:22px clamp(16px,4vw,48px) 36px!important;max-width:1000px!important;width:100%!important;margin:0 auto!important}
body.chat-layout .hero,body.chat-layout .welcome,body.chat-layout .main>.grid{display:none!important}
body.chat-layout #page-chat{display:flex!important;flex-direction:column;min-height:calc(100vh - 125px)}#page-chat .sectionhead{display:none!important}
#page-chat .glass.panel{background:transparent!important;border:0!important;box-shadow:none!important;padding:0!important;display:flex;flex-direction:column;flex:1;min-height:0}
#page-chat .chatlog{height:auto!important;min-height:45vh;max-height:calc(100vh - 280px);flex:1;overflow-y:auto;padding:24px 0!important;gap:24px!important}
#page-chat .bubble{max-width:min(88%,760px)!important;border-radius:18px!important;line-height:1.75!important;padding:12px 16px!important}
#page-chat .bubble.user{background:#303030!important;border:1px solid #414141!important;color:#f4f4f4!important}#page-chat .bubble.ai{background:transparent!important;border:0!important;padding-left:0!important;color:#ececec!important}
#page-chat .chatrow{position:sticky;bottom:8px;align-items:flex-end!important;gap:8px!important;padding:8px!important;background:#303030!important;border:1px solid #505050!important;border-radius:26px!important;box-shadow:0 8px 30px #0003}
#page-chat .chatrow textarea{background:transparent!important;border:0!important;box-shadow:none!important;resize:none!important;min-height:44px!important;max-height:180px!important;padding:12px 14px!important;color:#fff!important}
#page-chat .chatrow .btn{width:42px!important;height:42px!important;flex:0 0 42px!important;padding:0!important;border-radius:50%!important;background:#f4f4f4!important;color:#171717!important;box-shadow:none!important;font-size:0!important}#page-chat .chatrow .btn:after{content:"↑";font-size:22px;font-weight:700}
.glass,.panel,.auth{background:#262626!important;border-color:#414141!important;box-shadow:none!important;backdrop-filter:none!important}.field input,.field textarea,.field select{background:#212121!important;border-color:#505050!important;color:#f5f5f5!important}.btn{background:#f4f4f4!important;color:#202020!important;box-shadow:none!important}.btn.secondary{background:#353535!important;color:#eee!important;border-color:#555!important}
.navcard{background:#262626!important;border-color:#414141!important;box-shadow:none!important}.footer{color:#777!important}
@media(max-width:760px){.top{padding:10px 14px!important}.app{display:flex!important;flex-direction:column!important;min-height:calc(100vh - 58px)}.side{top:58px!important;height:auto!important;position:sticky!important;z-index:12;display:flex!important;overflow-x:auto!important;overflow-y:hidden!important;border:0!important;border-bottom:1px solid #333!important;padding:7px!important;gap:5px!important;background:rgba(23,23,23,.97)!important}.side .nav{flex:0 0 auto!important;width:auto!important;white-space:nowrap!important;margin:0!important;padding:9px 11px!important;font-size:12px!important}.side>div{display:flex!important;flex:0 0 auto!important;border:0!important;margin:0!important;padding:0!important}.main{padding:16px 14px 26px!important}body.chat-layout #page-chat{min-height:calc(100vh - 170px)}#page-chat .chatlog{max-height:calc(100vh - 275px);min-height:35vh}#page-chat .bubble{max-width:96%!important}}
@media(prefers-reduced-motion:reduce){*,*:before,*:after{animation:none!important;transition:none!important}}
</style>
<script id="novaryx-chat-default">
(function(){var originalShowApp=window.showApp;if(typeof originalShowApp==="function"){window.showApp=function(){originalShowApp();document.body.classList.add("chat-layout");if(typeof window.goPage==="function")window.goPage("chat");};}document.addEventListener("DOMContentLoaded",function(){var input=document.getElementById("chatInput");if(input){input.placeholder="Message NOVARYX-AI";input.addEventListener("keydown",function(e){if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();var form=document.getElementById("chatForm");if(form)form.requestSubmit();}});}});})();
</script>\`;
    const scriptStart = chatUi.indexOf('<script id="novaryx-chat-default">');
    const enhancedHtml = html.replace("</head>", chatUi.slice(0, scriptStart) + "</head>").replace("</body>", chatUi.slice(scriptStart) + "</body>");
    res.writeHead(200, {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-cache",
      "x-content-type-options": "nosniff",
    });
    return res.end(enhancedHtml);
  }

  if (req.method === "GET" && url.pathname === "/health") {
    return sendJson(res, 200, {
      name: "NOVARYX-AI API",
      status: "online",
      configured: isValidSupabaseConfig(),
      website: "served",
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
  console.log(`NOVARYX-AI web interface and API listening on port ${PORT}`);
});
