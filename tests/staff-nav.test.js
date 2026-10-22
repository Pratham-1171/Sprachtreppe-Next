const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {load, closeAll} = require('./harness');
const {build, FAKE_ANON, URL: SB} = require('./build-helper');
const {createServer} = require('./mock-supabase');

test.after(closeAll);
const PW = 'Correct-Horse-9';
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const $ = (w, selector) => w.document.querySelector(selector);
const realErrors = errors => errors.filter(e => !/scrollTo|Not implemented/.test(e));
let htmlPath;
function builtLmsPage() {
  if (htmlPath) return htmlPath;
  const base = build({SUPABASE_URL: SB, SUPABASE_ANON_KEY: FAKE_ANON});
  const lms = fs.readFileSync(path.join(__dirname, '../course/lms-ui.js'), 'utf8');
  const html = fs.readFileSync(base, 'utf8').replace('</body>', '<script>' + lms + '</script></body>');
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'sp-lms-nav-'));
  htmlPath = path.join(folder, 'index.html');
  fs.writeFileSync(htmlPath, html, 'utf8');
  return htmlPath;
}
function boot(server) {
  return load(builtLmsPage(), {before(w) { w.fetch = server.fetch; if (server.setupWindow) server.setupWindow(w); }});
}
async function login(w, email, who) {
  await wait(400);
  if (who === 'admin') {
    $(w, '[data-who=admin]').click();
    await wait(10);
  }
  $(w, '#spEmail').value = email;
  if ($(w, '#spPw')) $(w, '#spPw').value = PW;
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(250);
}
async function routes(w) {
  await wait(100);
  return [...w.document.querySelectorAll('#nav button[data-route]')].map(b => b.dataset.route);
}
async function attemptForbiddenRoute(w, route) {
  w.location.hash = '#/' + route;
  await wait(120);
  return w.location.hash;
}

test('teachers only see classroom, assignments and announcements; learning routes redirect', async () => {
  const server = createServer();
  server.addUser('teacher@school.org', PW, {role: 'teacher', approved: true, name: 'Test Teacher'});
  const {window: w, errors} = boot(server);
  await login(w, 'teacher@school.org');
  await wait(800);
  assert.equal(w.SP_LMS.isStaff(), true);
  const nav = await routes(w);
  assert.deepEqual(nav, ['classroom', 'students', 'assignments', 'announcements', 'notifications', 'audit']);
  assert.ok(!nav.some(r => ['home','session','review','vocab','grammar','quiz','flash','read','write','exam','progress','settings'].includes(r)));
  assert.equal(await attemptForbiddenRoute(w, 'grammar'), '#/assignments');
  assert.equal(await attemptForbiddenRoute(w, 'quiz'), '#/assignments');
  assert.ok(!realErrors(errors).length, realErrors(errors).join('\\n'));
});

test('admins see only review and LMS-management tabs, not the exercise course', async () => {
  const server = createServer();
  server.addUser('admin@school.org', PW, {role: 'admin', approved: true, name: 'Test Admin'});
  const {window: w, errors} = boot(server);
  await login(w, 'admin@school.org', 'admin');
  await wait(800);
  assert.equal(w.SP_LMS.isStaff(), true);
  const nav = await routes(w);
  assert.deepEqual(nav, ['classroom','students','assignments','announcements','notifications','audit','teachers']);
  assert.ok(!nav.some(r => ['home','session','review','vocab','grammar','quiz','flash','read','write','exam','progress','settings'].includes(r)));
  assert.equal(await attemptForbiddenRoute(w, 'grammar'), '#/assignments');
  assert.equal(await attemptForbiddenRoute(w, 'session'), '#/assignments');
  assert.ok(!realErrors(errors).length, realErrors(errors).join('\\n'));
});

test('students keep the original learning tabs and LMS tabs', async () => {
  const server = createServer();
  server.addUser('student@school.org', PW, {role: 'student', approved: true, name: 'Test Student'});
  const {window: w, errors} = boot(server);
  await login(w, 'student@school.org');
  await wait(800);
  assert.equal(w.SP_LMS.isStaff(), false);
  const nav = await routes(w);
  assert.ok(nav.includes('grammar'));
  assert.ok(nav.includes('vocab'));
  assert.ok(nav.includes('quiz'));
  assert.ok(nav.includes('classroom'));
  assert.ok(nav.includes('assignments'));
  assert.ok(!realErrors(errors).length, realErrors(errors).join('\\n'));
});
