const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const PORT = Number(process.env.PORT || 10000);
const SUPABASE_URL = String(process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const SUPABASE_PUBLISHABLE_KEY = String(
  process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ""
).trim();
// Secret key is server-only and is never returned by /api/config.
const SUPABASE_SECRET_KEY = String(process.env.SUPABASE_SECRET_KEY || "").trim();
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
    const chatUi = `
<style id="novaryx-chatgpt-refresh">
:root{color-scheme:dark;--chat-bg:#080808;--chat-side:rgba(255,255,255,.035);--chat-panel:rgba(255,255,255,.07);--chat-line:rgba(255,255,255,.16);--chat-text:#f8f8f8;--chat-muted:#aaa}
body{background:radial-gradient(ellipse at 50% -15%,rgba(255,255,255,.12),transparent 48%),linear-gradient(145deg,#050505,#111,#050505)!important;color:var(--chat-text)!important}body:before{display:none!important}
.top{background:rgba(10,10,10,.72)!important;border:1px solid rgba(255,255,255,.1)!important;border-top:0!important;border-radius:0 0 22px 22px!important;position:sticky;top:0;z-index:20;padding:12px 20px!important;backdrop-filter:blur(28px) saturate(140%)!important;-webkit-backdrop-filter:blur(28px) saturate(140%)!important;box-shadow:0 10px 40px rgba(0,0,0,.3)!important}
.wrap{width:100%!important;max-width:none!important}.brand{letter-spacing:.02em!important}.logo{background:linear-gradient(145deg,#fff,#888)!important;color:#080808!important;border:1px solid rgba(255,255,255,.7)!important;box-shadow:0 0 22px rgba(255,255,255,.12)!important}.tag{display:none!important}
.app{grid-template-columns:255px minmax(0,1fr)!important;gap:0!important;padding:0!important;min-height:calc(100vh - 65px)}
.side{position:sticky!important;top:65px!important;height:calc(100vh - 65px)!important;overflow:auto!important;background:var(--chat-side)!important;border:1px solid rgba(255,255,255,.11)!important;border-radius:0 24px 24px 0!important;padding:14px 10px!important;backdrop-filter:blur(30px) saturate(130%)!important;-webkit-backdrop-filter:blur(30px) saturate(130%)!important;box-shadow:inset -1px 0 rgba(255,255,255,.05),12px 0 45px rgba(0,0,0,.2)!important}
.side .nav{color:#d1d1d1!important;border:1px solid transparent!important;border-radius:10px!important;padding:11px 12px!important;margin:3px 0!important}.side .nav.active,.side .nav:hover{background:#2d2d2d!important;border-color:#3b3b3b!important;color:white!important;box-shadow:none!important}
.main{padding:22px clamp(16px,4vw,48px) 36px!important;max-width:1000px!important;width:100%!important;margin:0 auto!important}
body.chat-layout .hero,body.chat-layout .welcome,body.chat-layout .main>.grid{display:none!important}
body.chat-layout #page-chat{display:flex!important;flex-direction:column;min-height:calc(100vh - 125px)}#page-chat .sectionhead{display:none!important}
#page-chat .glass.panel{background:transparent!important;border:0!important;box-shadow:none!important;padding:0!important;display:flex;flex-direction:column;flex:1;min-height:0}
#page-chat .chatlog{height:auto!important;min-height:45vh;max-height:calc(100vh - 280px);flex:1;overflow-y:auto;padding:24px 0!important;gap:24px!important}
#page-chat .bubble{max-width:min(88%,760px)!important;border-radius:18px!important;line-height:1.75!important;padding:12px 16px!important}
#page-chat .bubble.user{background:linear-gradient(145deg,rgba(255,255,255,.12),rgba(255,255,255,.055))!important;border:1px solid rgba(255,255,255,.17)!important;color:#fff!important;box-shadow:inset 0 1px rgba(255,255,255,.1),0 8px 28px rgba(0,0,0,.12)!important;backdrop-filter:blur(18px)!important}#page-chat .bubble.ai{background:transparent!important;border:0!important;padding-left:0!important;color:#ececec!important}
#page-chat .chatrow{position:sticky;bottom:8px;align-items:flex-end!important;gap:8px!important;padding:8px!important;background:rgba(25,25,25,.72)!important;border:1px solid rgba(255,255,255,.19)!important;border-radius:27px!important;box-shadow:inset 0 1px rgba(255,255,255,.11),0 18px 50px rgba(0,0,0,.4)!important;backdrop-filter:blur(30px) saturate(140%)!important;-webkit-backdrop-filter:blur(30px) saturate(140%)!important}
#page-chat .chatrow textarea{background:transparent!important;border:0!important;box-shadow:none!important;resize:none!important;min-height:44px!important;max-height:180px!important;padding:12px 14px!important;color:#fff!important}
#page-chat .chatrow .btn{width:42px!important;height:42px!important;flex:0 0 42px!important;padding:0!important;border-radius:50%!important;background:#f4f4f4!important;color:#171717!important;box-shadow:none!important;font-size:0!important}#page-chat .chatrow .btn:after{content:"↑";font-size:22px;font-weight:700}
.glass,.panel,.auth,.navcard{background:linear-gradient(145deg,rgba(255,255,255,.085),rgba(255,255,255,.025))!important;border:1px solid rgba(255,255,255,.16)!important;border-radius:22px!important;box-shadow:inset 0 1px rgba(255,255,255,.13),0 18px 55px rgba(0,0,0,.28)!important;backdrop-filter:blur(26px) saturate(130%)!important;-webkit-backdrop-filter:blur(26px) saturate(130%)!important}.field input,.field textarea,.field select{background:rgba(255,255,255,.055)!important;border:1px solid rgba(255,255,255,.16)!important;border-radius:16px!important;color:#f5f5f5!important;box-shadow:inset 0 1px rgba(255,255,255,.05)!important}.btn{background:linear-gradient(145deg,#fff,#d7d7d7)!important;color:#080808!important;border:1px solid rgba(255,255,255,.65)!important;border-radius:14px!important;box-shadow:0 7px 22px rgba(255,255,255,.075),inset 0 1px rgba(255,255,255,.7)!important}.btn.secondary{background:rgba(255,255,255,.055)!important;color:#f5f5f5!important;border:1px solid rgba(255,255,255,.17)!important;box-shadow:inset 0 1px rgba(255,255,255,.06)!important}
.navcard{background:#262626!important;border-color:#414141!important;box-shadow:none!important}.footer{color:#777!important}
@media(max-width:760px){.top{padding:10px 14px!important}.app{display:flex!important;flex-direction:column!important;min-height:calc(100vh - 58px)}.side{top:58px!important;height:auto!important;position:sticky!important;z-index:12;display:flex!important;overflow-x:auto!important;overflow-y:hidden!important;border:0!important;border-bottom:1px solid #333!important;padding:7px!important;gap:5px!important;background:rgba(23,23,23,.97)!important}.side .nav{flex:0 0 auto!important;width:auto!important;white-space:nowrap!important;margin:0!important;padding:9px 11px!important;font-size:12px!important}.side>div{display:flex!important;flex:0 0 auto!important;border:0!important;margin:0!important;padding:0!important}.main{padding:16px 14px 26px!important}body.chat-layout #page-chat{min-height:calc(100vh - 170px)}#page-chat .chatlog{max-height:calc(100vh - 275px);min-height:35vh}#page-chat .bubble{max-width:96%!important}}
@media(prefers-reduced-motion:reduce){*,*:before,*:after{animation:none!important;transition:none!important}}
/* Inline creation mode controls */
#novaryx-create-options{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:8px 0 10px;padding:0 4px;position:relative}#novaryx-create-options button,.novaryx-mode-chip{padding:8px 13px;border:1px solid rgba(167,139,250,.35);border-radius:999px;background:linear-gradient(120deg,rgba(124,58,237,.22),rgba(34,211,238,.12));color:#f5f3ff;font-size:13px}#novaryx-create-options .novaryx-mode-chip{background:linear-gradient(100deg,#7c3aed,#0891b2);border:0;font-weight:700}#novaryx-style-pop,#novaryx-more-pop{position:absolute;left:0;bottom:44px;z-index:60;min-width:190px;max-width:min(340px,88vw);padding:9px;border:1px solid rgba(167,139,250,.35);border-radius:18px;background:rgba(23,19,48,.97);box-shadow:0 16px 45px #0009;backdrop-filter:blur(24px)}#novaryx-style-pop{display:grid;grid-template-columns:1fr 1fr;gap:6px}#novaryx-style-pop button{border-radius:10px;text-align:left}#novaryx-more-pop{display:grid;gap:10px}#novaryx-more-pop label{display:grid;gap:5px;font-size:12px;color:#d9d4ef}#novaryx-more-pop select{background:#211b3c;color:white;border:1px solid #665a8b;border-radius:9px;padding:8px;width:100%}
/* Composer plus menu */
#novaryx-plus-wrap{position:relative;flex:0 0 42px;align-self:flex-end}#novaryx-plus{width:42px;height:42px;border-radius:50%;border:1px solid rgba(255,255,255,.2);background:rgba(255,255,255,.09);color:#fff;font-size:27px;line-height:1;display:grid;place-items:center;backdrop-filter:blur(18px)}#novaryx-plus:hover{background:rgba(255,255,255,.17)}#novaryx-create-menu{position:absolute;bottom:52px;left:0;width:min(270px,78vw);padding:8px;background:rgba(39,39,39,.96);border:1px solid rgba(255,255,255,.16);border-radius:22px;box-shadow:0 18px 55px #0009;backdrop-filter:blur(30px);z-index:50}#novaryx-create-menu button{width:100%;display:flex;align-items:center;gap:13px;padding:13px 12px;border:0;border-radius:14px;background:transparent;color:#f5f5f5;text-align:left}#novaryx-create-menu button:hover{background:#424242}#novaryx-create-menu .create-icon{width:38px;height:38px;display:grid;place-items:center;border-radius:50%;background:#444;font-size:19px}#novaryx-create-menu strong{display:block;font-size:14px}#novaryx-create-menu small{display:block;color:#aaa;font-size:11px;margin-top:2px}#page-chat .chatrow{position:sticky}#page-chat .chatrow textarea{min-width:0}
/* Large pill-style creation toolbar matching the supplied reference */
#novaryx-create-options{display:flex!important;align-items:center!important;gap:10px!important;flex-wrap:wrap!important;margin:12px 0 16px!important;padding:0 4px!important}
#novaryx-create-options .novaryx-mode-chip,#novaryx-create-options button{min-height:54px!important;padding:0 24px!important;border-radius:999px!important;font-size:clamp(14px,2.4vw,19px)!important;font-weight:500!important;letter-spacing:.1px!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;white-space:nowrap!important;border:1px solid rgba(125,150,255,.48)!important;background:linear-gradient(120deg,rgba(36,42,91,.94),rgba(15,42,73,.96))!important;color:#f7fbff!important;box-shadow:inset 0 1px rgba(255,255,255,.14),0 0 18px rgba(50,100,255,.08)!important;transition:background .18s,border-color .18s,box-shadow .18s,transform .18s!important}
#novaryx-create-options .novaryx-mode-chip{background:linear-gradient(110deg,#5145f5 0%,#0789e9 55%,#e52b87 100%)!important;border:0!important;font-weight:700!important;padding:0 26px!important}
#novaryx-create-options button:hover{border-color:#66c9ff!important;background:linear-gradient(120deg,rgba(26,89,176,.96),rgba(9,91,126,.96))!important;box-shadow:0 0 22px rgba(0,145,255,.22)!important;transform:translateY(-1px)}
#novaryx-create-options #novaryx-clear-mode{width:54px!important;min-width:54px!important;padding:0!important;font-size:25px!important;border-radius:50%!important}
#novaryx-create-options #novaryx-styles{min-width:125px!important}
#novaryx-create-options #novaryx-more{min-width:185px!important}
@media(max-width:520px){#novaryx-create-options{gap:7px!important}#novaryx-create-options .novaryx-mode-chip,#novaryx-create-options button{min-height:44px!important;padding:0 15px!important;font-size:14px!important}#novaryx-create-options #novaryx-styles{min-width:0!important}#novaryx-create-options #novaryx-more{min-width:0!important}#novaryx-create-options #novaryx-clear-mode{width:44px!important;min-width:44px!important;padding:0!important}}
/* Dynamic black-and-electric-blue liquid glass theme */
:root{color-scheme:dark;--chat-bg:#030712;--chat-side:rgba(5,18,38,.82);--chat-panel:rgba(7,25,48,.72);--chat-line:rgba(56,189,248,.28);--chat-text:#f1f8ff;--chat-muted:#91a9c5;--blue:#168bff;--cyan:#22d3ee}
html{background:#030712!important}
body{color:#f1f8ff!important;background:radial-gradient(ellipse at 12% 4%,rgba(0,110,255,.3),transparent 34%),radial-gradient(ellipse at 88% 24%,rgba(0,212,255,.18),transparent 30%),radial-gradient(ellipse at 50% 110%,rgba(22,70,180,.24),transparent 40%),linear-gradient(145deg,#02040b,#061326 52%,#020611)!important;background-attachment:fixed!important}
body:before{content:"";display:block!important;position:fixed;inset:-20%;z-index:-1;pointer-events:none;background:radial-gradient(circle at 28% 35%,rgba(0,119,255,.2),transparent 28%),radial-gradient(circle at 70% 62%,rgba(34,211,238,.13),transparent 27%);filter:blur(44px);animation:novaryxBlueFlow 14s ease-in-out infinite alternate}
@keyframes novaryxBlueFlow{0%{transform:translate3d(-1%,0,0) scale(1)}100%{transform:translate3d(2%,-2%,0) scale(1.08)}}
.top{background:rgba(3,10,24,.78)!important;border:1px solid rgba(56,189,248,.18)!important;border-top:0!important;box-shadow:0 12px 42px rgba(0,70,180,.18)!important;backdrop-filter:blur(32px) saturate(155%)!important;-webkit-backdrop-filter:blur(32px) saturate(155%)!important}
.side{background:linear-gradient(180deg,rgba(4,21,44,.91),rgba(3,10,26,.9))!important;border-color:rgba(56,189,248,.22)!important;box-shadow:inset -1px 0 rgba(125,211,252,.08),12px 0 45px rgba(0,0,0,.28)!important;backdrop-filter:blur(32px) saturate(150%)!important;-webkit-backdrop-filter:blur(32px) saturate(150%)!important}
.side .nav{color:#b7cce4!important;border-color:transparent!important}.side .nav.active,.side .nav:hover{background:linear-gradient(110deg,rgba(0,119,255,.27),rgba(34,211,238,.13))!important;border-color:rgba(56,189,248,.27)!important;color:#fff!important;box-shadow:inset 0 1px rgba(255,255,255,.08),0 0 22px rgba(0,119,255,.1)!important}
.logo{background:linear-gradient(135deg,#dff7ff,#38bdf8 48%,#1677ff)!important;color:#02101f!important;border:1px solid rgba(186,230,253,.7)!important;box-shadow:0 0 28px rgba(0,145,255,.38)!important}
.glass,.panel,.auth,.navcard{background:linear-gradient(135deg,rgba(8,35,67,.76),rgba(4,17,37,.77),rgba(5,49,76,.48))!important;border:1px solid rgba(56,189,248,.24)!important;border-radius:22px!important;box-shadow:inset 0 1px rgba(255,255,255,.12),inset 0 -1px rgba(34,211,238,.05),0 20px 60px rgba(0,0,0,.32),0 0 28px rgba(0,119,255,.07)!important;backdrop-filter:blur(28px) saturate(155%)!important;-webkit-backdrop-filter:blur(28px) saturate(155%)!important}
.btn{background:linear-gradient(110deg,#0877ff,#06b6d4)!important;color:#fff!important;border:1px solid rgba(125,211,252,.48)!important;border-radius:14px!important;box-shadow:0 8px 28px rgba(0,119,255,.28),inset 0 1px rgba(255,255,255,.24)!important}.btn.secondary{background:linear-gradient(120deg,rgba(0,119,255,.18),rgba(34,211,238,.09))!important;color:#eaf7ff!important;border:1px solid rgba(56,189,248,.26)!important}
.field input,.field textarea,.field select{background:rgba(2,12,28,.62)!important;border:1px solid rgba(56,189,248,.24)!important;color:#f1f8ff!important;box-shadow:inset 0 1px rgba(255,255,255,.04)!important}.field input:focus,.field textarea:focus,.field select:focus{border-color:#22d3ee!important;box-shadow:0 0 0 3px rgba(34,211,238,.12),0 0 24px rgba(0,119,255,.12)!important}
#page-chat .bubble.user{background:linear-gradient(135deg,rgba(0,105,255,.3),rgba(34,211,238,.13))!important;border-color:rgba(56,189,248,.3)!important;color:#f3fbff!important;box-shadow:inset 0 1px rgba(255,255,255,.09),0 10px 28px rgba(0,0,0,.15)!important}
#page-chat .chatrow{background:linear-gradient(115deg,rgba(4,23,49,.9),rgba(3,34,58,.88),rgba(4,15,38,.92))!important;border-color:rgba(56,189,248,.38)!important;box-shadow:inset 0 1px rgba(255,255,255,.12),0 0 34px rgba(0,119,255,.15),0 18px 52px rgba(0,0,0,.42)!important;backdrop-filter:blur(34px) saturate(160%)!important;-webkit-backdrop-filter:blur(34px) saturate(160%)!important}
#page-chat .chatrow .btn{background:linear-gradient(135deg,#0877ff,#22d3ee)!important;color:#00101e!important;box-shadow:0 0 20px rgba(0,145,255,.24)!important}
#novaryx-plus{background:linear-gradient(135deg,#0877ff,#06b6d4)!important;border-color:rgba(125,211,252,.6)!important;box-shadow:0 0 22px rgba(0,119,255,.28)!important;color:white!important}
#novaryx-create-menu,#novaryx-style-pop,#novaryx-more-pop{background:rgba(3,15,35,.97)!important;border-color:rgba(56,189,248,.34)!important;box-shadow:0 20px 55px rgba(0,0,0,.55),0 0 24px rgba(0,119,255,.12)!important;backdrop-filter:blur(32px)!important}
#novaryx-create-menu button:hover,#novaryx-style-pop button:hover{background:linear-gradient(110deg,rgba(0,119,255,.28),rgba(34,211,238,.14))!important}
#novaryx-create-menu button[data-create="image"] .create-icon{background:linear-gradient(135deg,#1677ff,#38bdf8)!important}#novaryx-create-menu button[data-create="video"] .create-icon{background:linear-gradient(135deg,#0369a1,#22d3ee)!important}#novaryx-create-menu button[data-create="music"] .create-icon{background:linear-gradient(135deg,#1d4ed8,#06b6d4)!important}
#novaryx-create-options button,.novaryx-mode-chip{background:linear-gradient(120deg,rgba(0,119,255,.2),rgba(34,211,238,.11))!important;border-color:rgba(56,189,248,.3)!important;color:#effaff!important}#novaryx-create-options .novaryx-mode-chip{background:linear-gradient(110deg,#075be6,#0891b2)!important;color:#fff!important}
#novaryx-more-pop select{background:#061a33!important;color:#fff!important;border-color:#1677ff!important}
.navcard:hover{border-color:rgba(34,211,238,.5)!important;box-shadow:0 0 30px rgba(0,119,255,.13)!important}
@media(prefers-reduced-motion:reduce){body:before{animation:none!important}}
</style>
<script id="novaryx-chat-default">
(function(){var originalShowApp=window.showApp;if(typeof originalShowApp==="function"){window.showApp=function(){originalShowApp();document.body.classList.add("chat-layout");if(typeof window.goPage==="function")window.goPage("chat");};}document.addEventListener("DOMContentLoaded",function(){var input=document.getElementById("chatInput");if(input){input.placeholder="Message NOVARYX-AI";input.addEventListener("keydown",function(e){if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();var form=document.getElementById("chatForm");if(form)form.requestSubmit();}});var row=input.closest(".chatrow");if(row&&!document.getElementById("novaryx-plus-wrap")){var wrap=document.createElement("div");wrap.id="novaryx-plus-wrap";var plus=document.createElement("button");plus.id="novaryx-plus";plus.type="button";plus.setAttribute("aria-label","Create");plus.setAttribute("aria-expanded","false");plus.textContent="+";var menu=document.createElement("div");menu.id="novaryx-create-menu";menu.className="hidden";menu.innerHTML='<button type="button" data-create="image"><span class="create-icon">▧</span><span><strong>Image generation</strong><small>Create images from a prompt</small></span></button><button type="button" data-create="video"><span class="create-icon">▷</span><span><strong>Video generation</strong><small>Make AI video clips</small></span></button><button type="button" data-create="music"><span class="create-icon">♫</span><span><strong>Music generation</strong><small>Create original music</small></span></button>';wrap.appendChild(plus);wrap.appendChild(menu);row.insertBefore(wrap,input);plus.addEventListener("click",function(e){e.preventDefault();menu.classList.toggle("hidden");plus.setAttribute("aria-expanded",String(!menu.classList.contains("hidden")));});menu.querySelectorAll("[data-create]").forEach(function(item){item.addEventListener("click",function(){var page=item.getAttribute("data-create");menu.classList.add("hidden");plus.setAttribute("aria-expanded","false");var labels={image:"Describe the image you want to create",video:"Describe the video you want to create",music:"Describe the music you want to create"};input.placeholder=labels[page]||"Describe what you want to create";input.dataset.createMode=page;var oldBar=document.getElementById("novaryx-create-options");if(oldBar)oldBar.remove();var bar=document.createElement("div");bar.id="novaryx-create-options";bar.innerHTML='<span class="novaryx-mode-chip">'+({image:"✦ Image",video:"▶ Video",music:"♫ Music"}[page]||page)+'</span><button type="button" id="novaryx-styles">Styles</button><button type="button" id="novaryx-more">More options</button><button type="button" id="novaryx-clear-mode" aria-label="Close creation mode">×</button>';row.parentNode.insertBefore(bar,row);bar.querySelector("#novaryx-styles").addEventListener("click",function(){var old=document.getElementById("novaryx-style-pop");if(old){old.remove();return;}var pop=document.createElement("div");pop.id="novaryx-style-pop";var choices=page==="image"?["Photorealistic","Anime","Cinematic","3D render","Watercolor","Fantasy","Minimalist"]:page==="video"?["Cinematic","Anime","Realistic","3D animation","Slow motion","Dreamlike"]:["Afrobeats","Afro-pop","Amapiano","Hip-hop","R&B","Gospel","Lo-fi"];pop.innerHTML=choices.map(function(s){return '<button type="button" aria-pressed="false" style="display:block;width:100%;text-align:left;padding:10px 12px;margin:4px 0;border:1px solid rgba(56,189,248,.25);border-radius:12px;background:rgba(8,25,50,.8);color:#eaf7ff;cursor:pointer">'+s+'</button>'}).join("");bar.appendChild(pop);pop.querySelectorAll("button").forEach(function(b){b.addEventListener("click",function(){pop.querySelectorAll("button").forEach(function(x){x.style.background="rgba(8,25,50,.8)";x.style.borderColor="rgba(56,189,248,.25)";x.style.boxShadow="none";x.setAttribute("aria-pressed","false");});b.style.background="linear-gradient(110deg,rgba(0,119,255,.55),rgba(34,211,238,.3))";b.style.borderColor="#22d3ee";b.style.boxShadow="0 0 18px rgba(0,145,255,.25)";b.setAttribute("aria-pressed","true");var style=b.textContent;input.dataset.createStyle=style;input.placeholder="Describe your "+page+" · Style: "+style;var previous=input.value.replace(/(?:^|, )Style: [^,]+/g,"").trim();input.value=(previous?previous+", ":"")+"Style: "+style;input.focus();});});});bar.querySelector("#novaryx-more").addEventListener("click",function(){var old=document.getElementById("novaryx-more-pop");if(old){old.remove();return;}var pop=document.createElement("div");pop.id="novaryx-more-pop";var opts=page==="image"?[["Aspect ratio","1:1, 16:9, 9:16, 4:3"],["Quality","Standard, High detail"],["Number of images","1, 2, 4"]]:page==="video"?[["Aspect ratio","16:9, 9:16, 1:1"],["Duration","5s, 10s, 15s"],["Motion","Low, Medium, High"]]:[["Duration","30s, 60s, 120s"],["Mood","Happy, Dark, Chill, Energetic"],["Vocals","Instrumental, AI vocals"]];pop.innerHTML=opts.map(function(o,i){return '<label>'+o[0]+'<select data-option="'+i+'">'+o[1].split(", ").map(function(v){return '<option>'+v+'</option>'}).join("")+'</select></label>'}).join("");bar.appendChild(pop);});bar.querySelector("#novaryx-clear-mode").addEventListener("click",function(){bar.remove();input.dataset.createMode="";input.placeholder="Message NOVARYX-AI";var a=document.getElementById("novaryx-style-pop");if(a)a.remove();var b=document.getElementById("novaryx-more-pop");if(b)b.remove();});});});document.addEventListener("click",function(e){if(!wrap.contains(e.target)){menu.classList.add("hidden");plus.setAttribute("aria-expanded","false");}});}}});})();
</script>`;
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
          "apikey": SUPABASE_SECRET_KEY || SUPABASE_PUBLISHABLE_KEY,
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
