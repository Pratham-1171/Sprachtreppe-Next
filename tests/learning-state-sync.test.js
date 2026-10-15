const test = require('node:test');
const assert = require('node:assert');
const {load, closeAll} = require('./harness');
const {build, FAKE_ANON, URL: SB} = require('./build-helper');
const {createServer} = require('./mock-supabase');

test.after(closeAll);
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const PW = 'Correct-Horse-9';

function boot(server) {
  return load(build({SUPABASE_URL: SB, SUPABASE_ANON_KEY: FAKE_ANON}), {
    before(w) { w.fetch = server.fetch; }
  });
}
const $ = (w, selector) => w.document.querySelector(selector);

async function signIn(w, email) {
  await wait(300);
  $(w, '#spEmail').value = email;
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(100);
  assert.ok($(w, '#spCode'), 'sign-in should request an email OTP');
  $(w, '#spCode').value = '482913';
  $(w, '#spForm').dispatchEvent(new w.Event('submit', {cancelable: true, bubbles: true}));
  await wait(450);
}

test('state merge preserves mastered vocabulary, grammar completion, mistakes and study history', () => {
  const {window: w} = boot(createServer());
  const merge = w.SP_AUTH.mergeLearningStates;
  const remote = {
    mastery: {v17: {status: 'MASTERED', seen: 3}},
    grammarDone: {weil: true},
    mistakes: {v17: {count: 3}},
    sessionHistory: [{id: 's1', questions: 5}],
    practiceActivity: {'2026-10-15': {answers: 5}}
  };
  const local = {
    mastery: {v17: {status: 'WEAK', seen: 6}, v18: {status: 'LEARNING'}},
    grammarDone: {dass: true},
    mistakes: {v17: {count: 2}, v18: {count: 1}},
    sessionHistory: [{id: 's1', questions: 5}, {id: 's2', questions: 4}],
    practiceActivity: {'2026-10-15': {answers: 7}}
  };
  const merged = merge(remote, local);
  assert.equal(merged.mastery.v17.status, 'MASTERED');
  assert.equal(merged.mastery.v17.seen, 6);
  assert.equal(merged.mastery.v18.status, 'LEARNING');
  assert.deepEqual(merged.grammarDone, {weil: true, dass: true});
  assert.equal(merged.mistakes.v17.count, 3);
  assert.equal(merged.mistakes.v18.count, 1);
  assert.equal(merged.sessionHistory.length, 2, 'the same session must not be counted twice');
  assert.deepEqual(merged.practiceActivity['2026-10-15'].answers, 7);
});

test('a second device downloads and merges the saved course learning state on sign-in', async () => {
  const server = createServer();
  const student = server.addUser('cross-device@school.org', PW, {
    name: 'Cross Device Student', role: 'student', approved: true
  });
  const first = boot(server);
  await signIn(first.window, student.email);
  first.window.eval(\`
    S.mastery['vocab-v17'] = {status: 'MASTERED', lastSeen: Date.now(), seen: 4};
    S.grammarDone['weil'] = true;
    S.mistakes['vocab-v17'] = {count: 2, topic: 'Verben', lastSeen: Date.now()};
    S.sessionHistory.push({id: 'session-from-device-a', date: '2026-10-15', questions: 5, correct: 4});
    STORE.save();
  \`);
  await first.window.SP_AUTH.syncNow(true);
  const stored = server.learningStates.get(student.id);
  assert.equal(stored.mastery['vocab-v17'].status, 'MASTERED');
  assert.equal(stored.grammarDone.weil, true);
  assert.equal(stored.mistakes['vocab-v17'].count, 2);
  assert.ok(stored.sessionHistory.some(s => s.id === 'session-from-device-a'));

  const second = boot(server);
  await signIn(second.window, student.email);
  const imported = second.window.eval('S');
  assert.equal(imported.mastery['vocab-v17'].status, 'MASTERED');
  assert.equal(imported.grammarDone.weil, true);
  assert.equal(imported.mistakes['vocab-v17'].count, 2);
  assert.ok(imported.sessionHistory.some(s => s.id === 'session-from-device-a'));
});
