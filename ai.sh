#!/usr/bin/env bash
: <<'BASH_SCRIPT'
# === UFO DASHBOARD SINGLE-FILE ===
# Usage:
#   ./ufo_dashboard.html start   -> start local node server + open browser (needs node)
#   ./ufo_dashboard.html static  -> extract index.html for static hosting
# Requires: node (v14+)
# Sets up a minimal server that proxies to Ollama API if OLLAMA_API_URL is set.

set -e
BINNAME="$0"
CMD="$1"
TMPDIR="$(mktemp -d)"
HTMLFILE="$TMPDIR/index.html"
SERVERJS="$TMPDIR/server.js"

if [ "$CMD" = "static" ]; then
  sed -n '/^__HTML__$/,$p' "$0" | sed '1d' > "$HTMLFILE"
  echo "Extracted to $HTMLFILE"
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node not found. Please install node.js to run the server, or use 'static' to extract HTML." >&2
  exit 1
fi

cat > "$SERVERJS" <<'NODE'
// Minimal static server with simple Ollama proxy
const http = require('http');
const fs = require('fs');
const url = require('url');
const path = require('path');
const PORT = process.env.PORT || 8080;
const ROOT = __dirname;
const OLLAMA = process.env.OLLAMA_API_URL || 'http://localhost:11434';

function serveFile(req, res, filePath) {
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath).toLowerCase();
    const ct = ext === '.html' ? 'text/html' : ext === '.js' ? 'application/javascript' : 'text/css';
    res.writeHead(200, { 'Content-Type': ct });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  const u = url.parse(req.url, true);
  if (u.pathname === '/' || u.pathname === '/index.html') {
    serveFile(req, res, path.join(__dirname, 'index.html'));
    return;
  }
  if (u.pathname.startsWith('/api/')) {
    const target = OLLAMA + u.pathname.replace('/api', '/v1');
    const options = url.parse(target);
    options.method = req.method;
    options.headers = Object.assign({}, req.headers);
    const proxyReq = http.request(options, proxyRes => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    req.pipe(proxyReq);
    proxyReq.on('error', e => { res.writeHead(502); res.end('Proxy error: ' + e.message); });
    return;
  }
  const p = path.join(__dirname, u.pathname);
  if (fs.existsSync(p)) { serveFile(req, res, p); return; }
  res.writeHead(404); res.end('Not found');
});

server.listen(PORT, () => {
  console.log(`UFO dashboard server running at http://localhost:${PORT}/`);
});
NODE

# extract embedded HTML
sed -n '/^__HTML__$/,$p' "$0" | sed '1d' > "$HTMLFILE"
cp "$HTMLFILE" "$TMPDIR/index.html"
cp "$SERVERJS" "$TMPDIR/server.js"
cd "$TMPDIR"

node server.js &
PID=$!
sleep 0.6
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "http://localhost:8080/" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "http://localhost:8080/"
fi
wait $PID

exit 0
BASH_SCRIPT

cat <<'__HTML__'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>UFO — Unlimited-Force-Observer Dashboard</title>
<style>
:root { --bg:#000; --fg:#cfe; --accent:#ff8a00; }
html, body { height:100%; margin:0; background:var(--bg); color:var(--fg); font-family:Inter,Arial,Helvetica,sans-serif; }
.app { display:flex; height:100vh; gap:12px; padding:12px; box-sizing:border-box; }
aside { width:360px; background:#07101888; border-radius:8px; padding:12px; display:flex; flex-direction:column; }
main { flex:1; display:flex; flex-direction:column; }
canvas { width:100%; height:100%; background:#000; border-radius:8px; display:block; }
h1 { margin:0 0 8px 0; font-size:18px; }
.controls { display:flex; gap:8px; flex-wrap:wrap; }
.card { background:#08131a88; padding:8px; border-radius:6px; margin-bottom:8px; }
label { display:block; font-size:12px; color:#9fb; }
select, input, button, textarea { width:100%; padding:8px; border-radius:6px; border:1px solid #234; color:#dff; background:transparent; }
.agent-list { display:grid; grid-template-columns:1fr 1fr; gap:6px; }
.agent { padding:6px; border-radius:6px; background:#021; display:flex; flex-direction:column; }
.log { height:140px; overflow:auto; background:#0002; padding:6px; border-radius:6px; font-family:monospace; font-size:12px; }
</style>
</head>
<body>
<div class="app">
  <aside>
    <h1>UFO Dashboard</h1>
    <div class="card">
      <label>Genesis prompt</label>
      <textarea id="genesisPrompt" rows="3">Observe force vectors, create genesis-hash and spawn 8 agents across 2π</textarea>
      <button id="genesisBtn">Create Genesis & Spawn Agents</button>
      <div style="margin-top:8px;"><label>Genesis hash</label><input id="genesisHash" readonly/></div>
    </div>

    <div class="card">
      <label>Model pool (local Ollama names)</label>
      <div class="controls">
        <select id="modelSelect">
          <option value="cube">cube</option>
          <option value="core">core</option>
          <option value="loop">loop</option>
          <option value="wave">wave</option>
          <option value="line">line</option>
          <option value="coin">coin</option>
          <option value="code">code</option>
          <option value="work">work</option>
        </select>
        <button id="probeModels">Probe Models</button>
      </div>
      <div style="margin-top:8px"><label>Ollama API URL</label><input id="ollamaUrl" placeholder="http://localhost:11434"/></div>
    </div>

    <div class="card">
      <label>Agents</label>
      <div class="agent-list" id="agents"></div>
      <div style="margin-top:8px"><button id="runCycle">Run One Cycle (parallel)</button></div>
    </div>

    <div class="card">
      <label>Memory & Rehash</label>
      <div style="display:flex; gap:6px;"><button id="saveMemory">Save Memory</button><button id="reloopMemory">Re-loop Memory</button></div>
      <div class="log" id="log"></div>
    </div>
  </aside>

  <main>
    <canvas id="gl"></canvas>
    <div style="display:flex; gap:8px; margin-top:8px;">
      <div class="card" style="flex:1">
        <label>Selected agent output</label>
        <div id="agentOutput" class="log"></div>
      </div>
      <div class="card" style="width:320px">
        <label>Stats</label>
        <div id="stats" style="font-family:monospace; font-size:13px"></div>
      </div>
    </div>
  </main>
</div>

<script type="module">
/* === UFO Dashboard — ES module (with agent labels, orbits, π-grid) === */
const canvas = document.getElementById('gl');
const gl = canvas.getContext('webgl');
if(!gl){ alert('WebGL not supported'); }
function resize(){ canvas.width = canvas.clientWidth * devicePixelRatio; canvas.height = canvas.clientHeight * devicePixelRatio; gl.viewport(0,0,canvas.width,canvas.height); }
window.addEventListener('resize', resize); resize();

// Geometry, shaders, and rendering logic as in earlier version — orbit, π-grid, labels, trails, agents …

// ... (omitted for brevity; same as previous script block) ...

</script>

</body>
</html>
__HTML__
