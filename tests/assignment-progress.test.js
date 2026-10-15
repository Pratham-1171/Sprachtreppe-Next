const test = require('node:test');
const assert = require('node:assert');
const {load, closeAll} = require('./harness');
const {build, FAKE_ANON, URL: SB} = require('./build-helper');
const {createServer} = require('./mock-supabase');

test.after(closeAll);
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const PW = 'Correct-Horse-9';
let html;
function page() {
  return html || (html = build({SUPABASE_URL: SB, SUPABASE_ANON_KEY: FAKE_ANON}));
}
function boot(server) {
  return load(page(), {before(w) { w.fetch = server.fetch; }});
}
const $ = (w, selector) => w.document.querySelector(selector);
async function signIn(w, email) {
  await wait(350);
  $('#spEmail' in w.document ? w : w, '#spEmail');
  $(w, '#spEmail').value = email;
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(120);
  assert.ok($(w, '#spCode'), 'sign-in should request an email OTP');
  $(w, '#spCode').value = '482913';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(300);
}

test('web assignment progress syncs online and retries an offline answer', async () => {
  const server = createServer();
  const student = server.addUser('assignment-student@school.org', PW, {
    name: 'Assignment Student', role: 'student', approved: true
  });
  const assignment = server.addAssignment({
    id: 41, title: 'A2 grammar practice', skill: 'grammar', target_count: 5
  });
  const {window: w, errors} = boot(server);
  await signIn(w, student.email);

  assert.equal(w.SP_LMS.isStaff(), false);
  w.location.hash = '#/assignments';
  await wait(350);
  assert.match($('#view', w.document)?.textContent || '', /A2 grammar practice/);

  const listStart = [...w.document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Start practice');
  assert.ok(listStart, 'assignment card should offer the task details');
  listStart.click();
  await wait(80);
  const detailStart = [...w.document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Start practice');
  assert.ok(detailStart, 'assignment details should offer practice');
  detailStart.click();
  await wait(120);
  assert.equal(typeof w.recordPracticeActivity, 'function', 'real course recorder should be installed');

  // Two answers are acknowledged by the server.
  w.recordPracticeActivity('grammar', true);
  w.recordPracticeActivity('grammar', false);
  await wait(800);
  let progress = server.assignmentProgress.get(student.id + ':' + assignment.id);
  assert.deepEqual({done: progress && progress.done, correct: progress && progress.correct}, {done: 2, correct: 1});

  // A later answer is saved locally first; failed network writes must not advance the server.
  server.offline = true;
  w.recordPracticeActivity('grammar', true);
  await wait(800);
  progress = server.assignmentProgress.get(student.id + ':' + assignment.id);
  assert.deepEqual({done: progress && progress.done, correct: progress && progress.correct}, {done: 2, correct: 1});
  const local = JSON.parse(w.localStorage.getItem('sp_task_progress_v1_' + student.id));
  assert.equal(local[String(assignment.id)].done, 3);
  assert.equal(local[String(assignment.id)].correct, 2);
  assert.equal(local[String(assignment.id)].serverSyncedDone, 2);

  // Reconnection flushes the retained cumulative snapshot to the same RPC.
  server.offline = false;
  w.dispatchEvent(new w.Event('online'));
  await wait(900);
  progress = server.assignmentProgress.get(student.id + ':' + assignment.id);
  assert.deepEqual({done: progress && progress.done, correct: progress && progress.correct}, {done: 3, correct: 2});
  assert.ok(server.log.some(line => line === 'POST /rest/v1/rpc/update_assignment_progress'));
  assert.deepEqual(errors.filter(e => !/scrollTo|Not implemented/.test(e)), []);
});
