const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = 3000;
const HOST = '0.0.0.0';
const WWW_DIR = path.join(__dirname, 'www');

// Ensure www/index.html is built
if (!fs.existsSync(path.join(WWW_DIR, 'index.html'))) {
  console.log('[DevServer] www/index.html not found, building...');
  try {
    execSync('python3 scripts/build-course.py', {
      stdio: 'inherit',
      env: { ...process.env, ALLOW_LOCAL_MODE: '1' }
    });
  } catch (err) {
    console.error('[DevServer] Build failed:', err);
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

server.listen(PORT, HOST, () => {
  console.log(`[DevServer] Sprachtreppe serving on http://${HOST}:${PORT}`);
});
