const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const pythonCommand = require('./scripts/python');

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0'; // 0.0.0.0 lets a phone on the same Wi-Fi reach the dev server
const WWW_DIR = path.join(__dirname, 'www');

// Ensure www/index.html is built
if (!fs.existsSync(path.join(WWW_DIR, 'index.html'))) {
  console.log('[DevServer] www/index.html not found, building...');
  const r = spawnSync(pythonCommand(), [path.join(__dirname, 'scripts', 'build-course.py')], {
    stdio: 'inherit',
    env: { ...process.env, ALLOW_LOCAL_MODE: '1' }
  });
  if (r.error || r.status !== 0) {
    console.error('[DevServer] Build failed:', r.error ? r.error.message : 'exit code ' + r.status);
  }
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf'
};

const server = http.createServer((req, res) => {
  const reqUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  let pathname = decodeURIComponent(reqUrl.pathname);

  if (pathname === '/') {
    pathname = '/index.html';
  }

  let filePath = path.join(WWW_DIR, pathname);

  // Prevent directory traversal
  if (!filePath.startsWith(WWW_DIR)) {
    res.statusCode = 403;
    res.end('Forbidden');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Missing files with an extension (js, css, png...) must be a real 404,
      // otherwise a broken asset path silently returns the HTML page.
      if (path.extname(pathname)) {
        res.statusCode = 404;
        res.end('Not found: ' + pathname);
        return;
      }
      filePath = path.join(WWW_DIR, 'index.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (readErr, data) => {
      if (readErr) {
        res.statusCode = 500;
        res.end('Error reading file');
        return;
      }
      res.setHeader('Content-Type', contentType);
      res.setHeader('Cache-Control', 'no-cache');
      res.end(data);
    });
  });
});

function describeBuild() {
  try {
    const html = fs.readFileSync(path.join(WWW_DIR, 'index.html'), 'utf8');
    const hasBackend = /window\.SP_CONFIG=\{"url"/.test(html);
    const hasLms = html.includes('viewClassroom');
    if (hasBackend && hasLms) return 'classroom build (login/sync + LMS)';
    return 'WARNING: ' + (hasBackend ? 'backend configured' : 'LOCAL MODE, no login/sync') +
      (hasLms ? '' : ', no LMS layer') + ' -- run "npm run build:lms" with SUPABASE_URL and SUPABASE_ANON_KEY set';
  } catch { return 'unknown (could not read www/index.html)'; }
}

server.listen(PORT, HOST, () => {
  console.log('[DevServer] Sprachtreppe is running');
  console.log('  This PC:  http://localhost:' + PORT);
  for (const list of Object.values(os.networkInterfaces())) {
    for (const n of list || []) {
      if (n.family === 'IPv4' && !n.internal) console.log('  Phone (same Wi-Fi):  http://' + n.address + ':' + PORT);
    }
  }
  console.log('  Serving: ' + describeBuild());
});
