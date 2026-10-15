const test = require('node:test'), assert = require('node:assert');
const {load, closeAll} = require('./harness'), {build, FAKE_ANON, URL: SB} = require('./build-helper'), {createServer} = require('./mock-supabase');
test.after(closeAll);
const wait = ms => new Promise(r => setTimeout(r, ms));
const real = errs => errs.filter(e => !/scrollTo|Not implemented/.test(e));
const PW = 'Correct-Horse-9';
let page;
const html = () => page || (page = build({SUPABASE_URL: SB, SUPABASE_ANON_KEY: FAKE_ANON}));
function boot(server, storage, setup) {
  const r = load(html(), {before(w) {
    w.fetch = server.fetch; if (server.setupWindow) server.setupWindow(w);
    Object.entries(storage || {}).forEach(([k, v]) => w.localStorage.setItem(k, v));
    if (setup) setup(w);
  }});
  return r;
}
const dump = w => { const o = {}; for (let i = 0; i < w.localStorage.length; i++) { const k = w.localStorage.key(i); o[k] = w.localStorage.getItem(k); } return o; };
const $ = (w, s) => w.document.querySelector(s);
async function fillLogin(w, email, credential, who) {
  if (who === 'admin') { $(w, '[data-who=admin]').click(); await wait(10); }
  if (!$(w, '#spCode')) {
    $(w, '#spEmail').value = email;
    $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
    await wait(120);
  }
  const code = $(w, '#spCode');
  if (!code) return;
  code.value = credential === PW || credential === '482913' ? '482913' : '000000';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(200);
}
const hash = async (w, h) => { w.location.hash = h; w.dispatchEvent(new w.HashChangeEvent('hashchange')); await wait(150); };

test('build safety: refuses to build without a backend, with a service_role key, or with a bad URL', () => {
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  assert.throws(() => build({SUPABASE_URL: '', SUPABASE_ANON_KEY: '', ALLOW_LOCAL_MODE: ''}), /No backend configured|Command failed/);
  const svc = b64({alg: 'HS256'}) + '.' + b64({role: 'service_role'}) + '.sigsigsigsigsigsigsigsigsigsigsig';
  assert.throws(() => build({SUPABASE_URL: SB, SUPABASE_ANON_KEY: svc}), /Command failed/);
  assert.throws(() => build({SUPABASE_URL: 'http://evil.example.com', SUPABASE_ANON_KEY: FAKE_ANON}), /Command failed/);
  const f = require('fs').readFileSync(html(), 'utf8');
  assert.ok(!/service_role/.test(f), 'no service key in the app'); assert.ok(f.includes(SB));
});
test('the app starts locked and uses OTP without storing a password', async () => {
  const s = createServer(); s.addUser('anna@school.org', PW, {name: 'Anna', approved: true});
  const {window: w, errors} = boot(s); await wait(500);
  assert.ok(w.document.body.classList.contains('sp-locked')); assert.ok($(w, '#spAuth'));
  await fillLogin(w, 'anna@school.org', 'wrong-password-1');
  assert.match($(w, '#spErr').textContent, /Invalid or expired code/); assert.ok($(w, '#spAuth'), 'still locked');
  await fillLogin(w, 'anna@school.org', PW);
  assert.ok(!$(w, '#spAuth'), 'unlocked'); assert.ok(!w.document.body.classList.contains('sp-locked'));
  const all = JSON.stringify(dump(w)) + JSON.stringify(w.SP_AUTH._state()) + w.document.documentElement.outerHTML.replace(/value="[^"]*"/g, '');
  assert.ok(!all.includes(PW), 'password must never be stored or rendered');
  assert.equal($(w, '#spPw'), null);
  assert.deepEqual(real(errors), []);
});
test('login errors are generic, offline is explained, and brute-force triggers a cooldown', async () => {
  const s = createServer(); s.addUser('a@x.org', PW, {approved: true});
  const {window: w} = boot(s); await wait(400);
  s.offline = true; await fillLogin(w, 'a@x.org', PW); assert.match($(w, '#spErr').textContent, /No internet/); s.offline = false;
  for (let i = 0; i < 5; i++) await fillLogin(w, 'a@x.org', 'bad-code-' + i);
  assert.match($(w, '#spErr').textContent, /Invalid or expired code/, 'generic response for invalid code');
  await fillLogin(w, 'a@x.org', PW); assert.match($(w, '#spErr').textContent, /Too many attempts/); assert.ok($(w, '#spAuth'));
});
test('student self-registration uses OTP, stays pending, and approved accounts can sync progress', async () => {
  const s = createServer(); const {window: w} = boot(s); await wait(400);
  $(w, '#spSwitch').click(); await wait(10);
  $(w, '#spName').value = 'Ben Student'; $(w, '#spEmail').value = 'ben@school.org';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(120);
  assert.ok($(w, '#spCode'), 'registration sends a one-time code');
  $(w, '#spCode').value = '482913';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(220);
  const u = s.users.get('ben@school.org');
  assert.ok(u); assert.equal(u.role, 'student'); assert.equal(u.approved, false); assert.equal(u.full_name, 'Ben Student');
  assert.ok($(w, '#spAuth'), 'registration does not keep the unapproved user signed in');
  assert.match($(w, '#spErr').textContent, /administrator must approve/i);
  assert.equal(dump(w)['sp-auth-v1'], undefined);
  u.approved = true;
  await fillLogin(w, 'ben@school.org', PW);
  assert.ok(!$(w, '#spAuth'), 'approved student can sign in with OTP');
  w.eval('S.practiceActivity={"2026-10-10":{answers:10,correct:7}};S.writingLog=[{t:1,level:"A1",title:"x",score:80,words:30,text:"Hallo"}];STORE.save()');
  await w.SP_AUTH.syncNow(true);
  assert.equal(s.subs.length, 1); assert.equal(s.subs[0].student_id, u.id);
  assert.equal(s.subs[0].summary.answers_7d, 10); assert.equal(s.subs[0].summary.correct_7d, 7);
  assert.equal(s.subs[0].payload.writing[0].text, 'Hallo');
  assert.ok(!JSON.stringify(s.subs[0]).includes(PW));
});
test('weekly rule: warning after 5 days, locked after 7, unlocked only by a successful sync', async () => {
  const s = createServer(); const u = s.addUser('c@x.org', PW, {approved: true, name: 'Clara'});
  const first = boot(s); await wait(400); await fillLogin(first.window, 'c@x.org', PW);
  const store = dump(first.window); const DAY = 86400000, now = Date.now();
  const seedSync = d => JSON.stringify(Object.assign(JSON.parse(store['sp-sync-v1']), {lastSyncLocal: now - d * DAY, hw: now}));
  let g = boot(s, Object.assign({}, store, {'sp-sync-v1': seedSync(5.5)})); await wait(500);
  assert.ok(!$(g.window, '#spLock')); assert.match($(g.window, '#spChip').textContent, /Sync in/);
  g = boot(s, Object.assign({}, store, {'sp-sync-v1': seedSync(8)})); await wait(500);
  assert.ok($(g.window, '#spLock'), 'locked after 8 days'); assert.ok(g.window.document.body.classList.contains('sp-locked'));
  s.offline = true; $(g.window, '#spLockSync').click(); await wait(150);
  assert.match($(g.window, '#spLockMsg').textContent, /No internet/); assert.ok($(g.window, '#spLock'), 'stays locked offline');
  s.offline = false; const before = s.subs.length; $(g.window, '#spLockSync').click(); await wait(250);
  assert.ok(!$(g.window, '#spLock'), 'unlocked after sync'); assert.equal(s.subs.length, before + 1);
  assert.ok(g.window.SP_AUTH.lockState().days < 0.01);
});
test('changing the device clock backwards does not escape the weekly lock', async () => {
  const s = createServer(); s.addUser('d@x.org', PW, {approved: true});
  const first = boot(s); await wait(400); await fillLogin(first.window, 'd@x.org', PW);
  const store = dump(first.window), DAY = 86400000, now = Date.now();
  store['sp-sync-v1'] = JSON.stringify(Object.assign(JSON.parse(store['sp-sync-v1']), {lastSyncLocal: now - 8 * DAY, hw: now}));
  const g = boot(s, store); await wait(500);
  g.window.eval('Date.now = () => ' + (now - 20 * DAY));
  assert.ok(g.window.SP_AUTH.lockState().locked, 'still locked with the clock set back 20 days');
  g.window.eval('Date.now = () => ' + (now - 20 * DAY) + '; void 0'); g.window.dispatchEvent(new g.window.Event('online')); await wait(100);
  assert.ok(g.window.SP_AUTH._state().sync.clockRewinds >= 1, 'rewind is recorded for the teacher');
});
test('admin console: lists students, escapes hostile text, reviews, feedback reaches the student', async () => {
  const s = createServer(); s.addUser('teacher@school.org', PW, {role: 'admin', approved: true, name: 'Teacher'});
  const evil = '<img src=x onerror="window.__xss=1">';
  const stu = s.addUser('e@x.org', PW, {approved: true, name: evil}); s.addUser('pending@x.org', PW, {name: 'Newbie'});
  s.subs.push({id: s.nextSub++, student_id: stu.id, client_id: 'client-evil-1', created_at: new Date().toISOString(), review_status: 'pending', review_note: null, rating: null, student_seen: true,
    summary: {answers_7d: 20, correct_7d: 15, active_days_7d: 4, streak: 3, grammar: {perfekt: {n: 10, ok: 3}}, skills: {}, study_seconds_total: 3600, words_known: 50},
    payload: {mistakes: [{topic: '<b>t</b>', prompt: '<script>window.__xss=2</script>', you: 'a', correct: 'b', count: 2}], writing: [{t: 1, level: 'A1', title: 'T', score: 55, words: 20, text: '<svg onload=window.__xss=3>'}]}});
  const {window: w, errors} = boot(s); await wait(400);
  await fillLogin(w, 'teacher@school.org', PW, 'admin'); assert.ok(!$(w, '#spAuth'));
  assert.ok([...w.document.querySelectorAll('#nav button, #nav a')].some(b => /Admin/.test(b.textContent)), 'admin tab visible');
  await hash(w, '#/admin'); const v = $(w, '#view');
  assert.match(v.textContent, /Awaiting approval|awaiting approval/i); assert.ok(v.textContent.includes('<img src=x')); assert.equal(v.querySelector('img'), null);
  v.querySelector('[data-open]'); const open = [...v.querySelectorAll('[data-open]')].find(b => b.dataset.open === stu.id); open.click(); await wait(250);
  assert.equal(w.__xss, undefined, 'no script ran'); assert.equal(v.querySelector('script, svg, img'), null);
  assert.ok(v.textContent.includes('<script>window.__xss=2</script>') && v.textContent.includes('<svg onload'));
  assert.match(v.textContent, /perfekt/);
  $(w, '[data-rev]').closest('.card').querySelector('textarea').value = 'Good progress, practise Perfekt.';
  $(w, '[data-rev][data-st=reviewed]').click(); await wait(250);
  assert.equal(s.subs[0].review_status, 'reviewed'); assert.equal(s.subs[0].review_note, 'Good progress, practise Perfekt.'); assert.equal(s.subs[0].student_seen, false);
  // approve the pending student
  $(w, '#admBack').click(); await wait(250);
  const pend = s.users.get('pending@x.org'); [...$(w, '#view').querySelectorAll('[data-open]')].find(b => b.dataset.open === pend.id).click(); await wait(250);
  $(w, '#admApprove').click(); await wait(250); assert.equal(pend.approved, true);
  assert.deepEqual(real(errors), []);
  // the student now receives the feedback on the next sync
  const sw = boot(s); await wait(400); await fillLogin(sw.window, 'e@x.org', PW); await sw.window.SP_AUTH.syncNow(true);
  assert.equal(sw.window.SP_AUTH._state().sync.feedback[0].note, 'Good progress, practise Perfekt.');
  assert.equal(s.subs[0].student_seen, true, 'feedback acknowledged');
});

test('administrator can promote an approved student to teacher and demote them again', async () => {
  const s = createServer();
  s.addUser('admin@school.org', PW, {role: 'admin', approved: true, name: 'Admin'});
  const student = s.addUser('to-promote@school.org', PW, {role: 'student', approved: true, name: 'Promote Me'});
  const {window: w, errors} = boot(s); w.confirm = () => true;
  await wait(400); await fillLogin(w, 'admin@school.org', PW, 'admin');
  await hash(w, '#/admin');
  const open = [...$(w, '#view').querySelectorAll('[data-open]')].find(b => b.dataset.open === student.id);
  assert.ok(open, 'admin can open the student record'); open.click(); await wait(180);
  assert.match($(w, '#view').textContent, /Promote to teacher/);
  $(w, '#admRoleBtn').click(); await wait(220);
  assert.equal(student.role, 'teacher'); assert.equal(student.approved, true);
  assert.match($(w, '#view').textContent, /Return to student/);
  $(w, '#admRoleBtn').click(); await wait(220);
  assert.equal(student.role, 'student'); assert.equal(student.approved, true);
  assert.deepEqual(real(errors), []);
});

test('a student cannot use the admin screen or the admin API', async () => {
  const s = createServer(); const stu = s.addUser('f@x.org', PW, {approved: true}); s.addUser('other@x.org', PW, {approved: true, name: 'Other'});
  const {window: w} = boot(s); await wait(400); await fillLogin(w, 'f@x.org', PW);
  await hash(w, '#/admin'); assert.match($(w, '#view').textContent, /Administrators only/);
  assert.ok(![...w.document.querySelectorAll('#nav *')].some(b => /Admin/.test(b.textContent)));
  const tok = w.SP_AUTH._state().auth.access_token, h = {apikey: 'k', Authorization: 'Bearer ' + tok};
  assert.equal(s.handle('POST', SB + '/rest/v1/rpc/admin_overview', h, {}).status, 403);
  assert.equal(s.handle('GET', SB + '/rest/v1/profiles?select=*', h).body.length, 1, 'sees only own profile');
  assert.equal(s.handle('PATCH', SB + '/rest/v1/profiles?id=eq.' + stu.id, h, {role: 'admin'}).body.length, 0, 'cannot promote self');
  assert.equal(stu.role, 'student');
});
async function adminCodeFlow(w, email, code) {
  $(w, '[data-who=admin]').click(); await wait(10);
  assert.equal($(w, '#spPw'), null, 'admin tab asks for a code, not a password');
  $(w, '#spEmail').value = email; $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(150);
  if (code === undefined) return;
  $(w, '#spEmail').value = email; $(w, '#spCode').value = code; $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(200);
}
test('admin signs in with an emailed one-time code (no password)', async () => {
  const s = createServer(); s.addUser('teacher@school.org', PW, {role: 'admin', approved: true, name: 'T'});
  const {window: w, errors} = boot(s); await wait(400);
  await adminCodeFlow(w, 'teacher@school.org', '000000');
  assert.match($(w, '#spErr').textContent, /Invalid or expired code/); assert.ok($(w, '#spAuth'), 'wrong code does not unlock');
  $(w, '#spCode').value = '482913'; $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(200);
  assert.ok(!$(w, '#spAuth'), 'correct code unlocks'); assert.ok(w.SP_AUTH.isAdmin());
  assert.ok(!JSON.stringify(dump(w)).includes('482913'), 'code is not stored');
  assert.deepEqual(real(errors), []);
});
test('emailed code: unknown emails look identical, students are refused, codes are single-use', async () => {
  const s = createServer(); s.addUser('teacher@school.org', PW, {role: 'admin', approved: true}); s.addUser('stu@school.org', PW, {approved: true});
  let page1 = boot(s); await wait(400);
  await adminCodeFlow(page1.window, 'nobody@school.org');
  const unknownMsg = $(page1.window, '#spErr').textContent;
  assert.match(unknownMsg, /If this email is eligible/); assert.ok($(page1.window, '#spCode'), 'same screen for unknown emails');
  const page2 = boot(s); await wait(400);
  await adminCodeFlow(page2.window, 'teacher@school.org');
  assert.equal($(page2.window, '#spErr').textContent, unknownMsg, 'identical message for a real administrator');
  // a student cannot use the admin tab, even with a valid code for his own account
  const page3 = boot(s); await wait(400);
  await adminCodeFlow(page3.window, 'stu@school.org'); s.otps['stu@school.org'] = '482913';
  $(page3.window, '#spEmail').value = 'stu@school.org'; $(page3.window, '#spCode').value = '482913';
  $(page3.window, '#spForm').dispatchEvent(new page3.window.Event('submit', {cancelable: true, bubbles: true})); await wait(200);
  assert.match($(page3.window, '#spErr').textContent, /not an administrator/); assert.ok($(page3.window, '#spAuth')); assert.equal(dump(page3.window)['sp-auth-v1'], undefined);
  // offline
  s.offline = true; $(page3.window, '#spEmail').value = 'stu@school.org'; $(page3.window, '#spCode').value = '482913';
  $(page3.window, '#spForm').dispatchEvent(new page3.window.Event('submit', {cancelable: true, bubbles: true})); await wait(150);
  assert.match($(page3.window, '#spErr').textContent, /No internet/); s.offline = false;
  // single use: first sign-in works, the same code fails afterwards
  const page4 = boot(s); await wait(400); await adminCodeFlow(page4.window, 'teacher@school.org', '482913'); assert.ok(!$(page4.window, '#spAuth'));
  const replay = s.handle('POST', SB + '/auth/v1/verify', {apikey: 'k'}, {type: 'email', email: 'teacher@school.org', token: '482913'});
  assert.equal(replay.status, 403, 'the same code cannot be used twice');
});
test('admin sign-in is OTP-only and cannot create users', async () => {
  const s = createServer(); s.addUser('teacher@school.org', PW, {role: 'admin', approved: true});
  const {window: w} = boot(s); await wait(400);
  assert.equal($(w, '#spPw'), null);
  $(w, '[data-who=admin]').click(); await wait(10);
  assert.equal($(w, '#spMethod'), null); assert.equal($(w, '#spSwitch'), null);
  $(w, '#spEmail').value = 'new@school.org';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true})); await wait(150);
  assert.equal(s.users.has('new@school.org'), false, 'admin tab cannot self-register');
  assert.ok($(w, '#spCode'));
  assert.ok(!s.log.some(x => x.includes('/auth/v1/token')), 'app never sends password grant requests');
});

test('unapproved accounts stay locked until approval', async () => {
  const s = createServer(); s.addUser('u@x.org', PW, {approved: false});
  const pending = boot(s); await wait(400); await fillLogin(pending.window, 'u@x.org', PW);
  assert.match($(pending.window, '#spErr').textContent, /waiting for administrator approval/i);
  assert.ok($(pending.window, '#spAuth')); assert.equal(dump(pending.window)['sp-auth-v1'], undefined);
  s.users.get('u@x.org').approved = true;
  const approved = boot(s); await wait(400); await fillLogin(approved.window, 'u@x.org', PW);
  assert.ok(!$(approved.window, '#spAuth'), 'approved account can enter with a fresh OTP');
});
test('admin tab with a student account is refused and leaves no session behind', async () => {
  const s = createServer(); s.addUser('g@x.org', PW, {approved: true});
  const {window: w} = boot(s); await wait(400); await fillLogin(w, 'g@x.org', PW, 'admin');
  assert.match($(w, '#spErr').textContent, /not an administrator/); assert.ok($(w, '#spAuth')); assert.equal(dump(w)['sp-auth-v1'], undefined);
});
test('two students on one phone keep separate progress', async () => {
  const s = createServer(); s.addUser('h1@x.org', PW, {approved: true}); s.addUser('h2@x.org', PW, {approved: true});
  const a = boot(s); await wait(400); await fillLogin(a.window, 'h1@x.org', PW);
  a.window.eval('S.streak={current:9,longest:9};STORE.save()'); const idA = a.window.SP_AUTH._state().auth.user.id;
  await a.window.SP_AUTH.signOut(); await wait(50); assert.ok($(a.window, '#spAuth'));
  await fillLogin(a.window, 'h2@x.org', PW); const d = dump(a.window);
  assert.ok(d['de-a1b1-v5@' + idA], 'first student\'s data is stored under their own key');
  assert.equal(JSON.parse(d['de-a1b1-v5@' + idA]).streak.current, 9); assert.equal(d['de-a1b1-v5'], undefined, 'second student starts clean');
});
