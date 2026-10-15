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

test('current streak follows the newest study date while longest streak never shrinks', () => {
  const {window: w} = boot(createServer());
  const merge = w.SP_AUTH.mergeLearningStates;
  const merged = merge(
    {streak: {current: 8, longest: 8, lastStudyDate: '2026-10-10'}},
    {streak: {current: 2, longest: 10, lastStudyDate: '2026-10-15'}}
  );
  assert.equal(merged.streak.current, 2, 'an updated streak is allowed to reset after a gap');
  assert.equal(merged.streak.longest, 10, 'the best-ever streak must be preserved');
  assert.equal(merged.streak.lastStudyDate, '2026-10-15');
});

test('a second device downloads and merges the saved course learning state on sign-in', async () => {
  const server = createServer();
  const student = server.addUser('cross-device@school.org', PW, {
    name: 'Cross Device Student', role: 'student', approved: true
  });
  const first = boot(server);
  await signIn(first.window, student.email);
  first.window.eval(`
    S.mastery['vocab-v17'] = {status: 'MASTERED', lastSeen: Date.now(), seen: 4};
    S.grammarDone['weil'] = true;
    S.mistakes['vocab-v17'] = {count: 2, topic: 'Verben', lastSeen: Date.now()};
    S.sessionHistory.push({id: 'session-from-device-a', date: '2026-10-15', questions: 5, correct: 4});
    STORE.save();
  `);
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

test('browser answer events are shared and idempotent across devices', async () => {
  const server = createServer();
  const student = server.addUser('events@school.org', PW, {name: 'Event Student', role: 'student', approved: true});
  const first = boot(server);
  await signIn(first.window, student.email);
  const firstAuth = first.window.SP_AUTH._state().auth;
  first.window.SP_AUTH.recordLearningAnswer({
    mode: 'vocabulary', entityType: 'vocabulary', entityId: 'haus',
    level: 'A1', topic: 'Home', prompt: 'Haus', answer: 'house',
    expected: 'house', correct: true
  });
  first.window.SP_AUTH.recordLearningAnswer({
    mode: 'grammar', entityType: 'grammar', entityId: 'weil-word-order',
    level: 'A2', topic: 'Word order', prompt: 'weil', correct: true
  });
  await first.window.SP_AUTH.syncLearningAnswerEvents(firstAuth.access_token);
  assert.equal(first.window.SP_AUTH.pendingLearningAnswerCount(), 0);
  assert.equal(server.learningAnswerEvents.get(student.id).size, 2);
  await first.window.SP_AUTH.syncLearningAnswerEvents(firstAuth.access_token);
  assert.equal(server.learningAnswerEvents.get(student.id).size, 2);
  const saved = server.learningStates.get(student.id);
  assert.equal(saved.flutter.summary.eventsTotal, 2);
  assert.equal(Object.hasOwn(saved.flutter, 'answerEvents'), false);

  const second = boot(server);
  await signIn(second.window, student.email);
  const secondAuth = second.window.SP_AUTH._state().auth;
  second.window.SP_AUTH.recordLearningAnswer({
    mode: 'vocabulary', entityType: 'vocabulary', entityId: 'lernen',
    level: 'A1', topic: 'School', prompt: 'lernen', correct: true
  });
  await second.window.SP_AUTH.syncLearningAnswerEvents(secondAuth.access_token);
  assert.equal(server.learningAnswerEvents.get(student.id).size, 3);
  assert.equal(server.learningStates.get(student.id).flutter.summary.eventsTotal, 3);

  await second.window.SP_AUTH.syncLearningState(secondAuth.access_token);
  const shared = server.learningStates.get(student.id).crossDeviceProgress;
  assert.ok(shared, 'the browser state should retain the server-owned native learning aggregates');
  assert.equal(shared.summary.eventsTotal, 3);
  assert.equal(shared.vocabularyMastery.haus.attempts, 1);
  assert.equal(shared.grammarCompletion['weil-word-order'].completed, true);
  assert.equal(second.window.eval('S.crossDeviceProgress.summary.eventsTotal'), 3,
    'the newly signed-in browser should apply shared aggregates to its own local learning state');
});

test('offline browser answers remain queued until the event RPC succeeds', async () => {
  const server = createServer();
  const student = server.addUser('offline-events@school.org', PW, {
    name: 'Offline Event Student', role: 'student', approved: true
  });
  const {window: w} = boot(server);
  await signIn(w, student.email);
  const accessToken = w.SP_AUTH._state().auth.access_token;

  w.SP_AUTH.recordLearningAnswer({
    mode: 'grammar', entityType: 'grammar', entityId: 'dass-word-order',
    level: 'A2', topic: 'Word order', prompt: 'dass', correct: false
  });
  server.offline = true;
  await assert.rejects(w.SP_AUTH.syncLearningAnswerEvents(accessToken));
  assert.equal(w.SP_AUTH.pendingLearningAnswerCount(), 1);
  server.offline = false;
  await w.SP_AUTH.syncLearningAnswerEvents(accessToken);
  assert.equal(w.SP_AUTH.pendingLearningAnswerCount(), 0);
  assert.equal(server.learningAnswerEvents.get(student.id).size, 1);
});

test('browser pulls native Flutter study sessions and keeps them in shared history', async () => {
  const server = createServer();
  const student = server.addUser('native-sessions@school.org', PW, {
    name: 'Native Session Student', role: 'student', approved: true
  });
  server.learningStates.set(student.id, {
    sessionHistory: [],
    flutter: {
      sessions: [{
        id: 'native-session-a',
        completedAt: '2026-10-15T10:00:00.000Z',
        mode: 'Grammar',
        level: 'A2',
        correct: 4,
        total: 5
      }],
      summary: {totalSessions: 1, bestStreak: 2}
    }
  });

  const {window: w} = boot(server);
  await signIn(w, student.email);
  await w.SP_AUTH.syncLearningState(w.SP_AUTH._state().auth.access_token);
  await w.SP_AUTH.syncLearningState(w.SP_AUTH._state().auth.access_token);

  const imported = w.eval("S.sessionHistory.filter(s => s.id === 'flutter-session:native-session-a')");
  assert.equal(imported.length, 1, 'repeated sync must not duplicate a native session');
  assert.equal(imported[0].questions, 5);
  assert.equal(imported[0].correct, 4);
  assert.equal(imported[0].source, 'flutter');
  assert.ok(server.learningStates.get(student.id).sessionHistory
    .some(s => s.id === 'flutter-session:native-session-a'));
});
