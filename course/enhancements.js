/* Shared enhancements for the embedded and downloadable course. */
function localStudyDate(date = new Date()) {
  return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
}
function recordPracticeActivity(skill, correct) {
  if (!S.practiceActivity) S.practiceActivity = {};
  const day = localStudyDate();
  const entry = S.practiceActivity[day] || { answers: 0, correct: 0, skills: {} };
  entry.answers++;
  if (correct) entry.correct++;
  entry.skills[skill] = (entry.skills[skill] || 0) + 1;
  S.practiceActivity[day] = entry;
  const stat = S.quizStats[skill] || { done: 0, correct: 0 };
  stat.done++; if (correct) stat.correct++;
  S.quizStats[skill] = stat;
  touchStreak(); STORE.save(); checkAchievements();
}
function practiceSnapshot() {
  const today = localStudyDate();
  const legacy = S.sessionHistory.filter(s => s.date === today).reduce((sum, s) => sum + s.questions, 0);
  const activeStreak = S.streak.lastStudyDate === today || S.streak.lastStudyDate === localStudyDate(new Date(Date.now() - 86400000));
  return {
    today: Math.max(S.practiceActivity?.[today]?.answers || 0, legacy),
    goal: S.settings.dailyGoal || 20,
    streak: activeStreak ? S.streak.current : 0,
    learned: Object.keys(S.mastery).filter(k => k.startsWith('v') && ['STRONG', 'MASTERED'].includes(S.mastery[k].status)).length,
    due: dueCount(), mistakes: Object.keys(S.mistakes).length, total: VOCAB.length, lang: S.settings.lang,
    words: VOCAB.filter(w => ['der', 'die', 'das'].includes(w.art)).map(({ n, art, de, en, level }) => ({ n, art, de, en, level })),
    labels: Object.fromEntries(NAV.map(([id, key]) => [id, t(key).replace(/^[^\p{L}\p{N}]+/u, '').trim()]))
  };
}
function announceCourseState() {
  if (window.parent === window) return;
  window.parent.postMessage({ source: 'german-course', type: 'snapshot', data: practiceSnapshot() }, window.location.origin);
}
const originalCourseSave = STORE.save.bind(STORE);
STORE.save = function () { originalCourseSave(); clearTimeout(window.snapshotTimer); window.snapshotTimer = setTimeout(announceCourseState, 30); };

window.addEventListener('message', event => {
  if (event.origin !== window.location.origin || event.source !== window.parent || event.data?.source !== 'practice-desk') return;
  const data = event.data;
  if (data.command === 'snapshot') announceCourseState();
  if (data.command === 'route' && NAV.some(([id]) => id === data.module)) {
    if (location.hash === '#/' + data.module) route();
    else location.hash = '#/' + data.module;
    announceCourseState();
  }
  if (data.command === 'language' && ['en', 'gu'].includes(data.lang)) { S.settings.lang = data.lang; STORE.save(); applyLanguage(true); announceCourseState(); }
  if (data.command === 'speak' && typeof data.text === 'string') speakGerman(data.text.slice(0, 500));
  if (data.command === 'answer') {
    const word = VOCAB.find(w => w.n === data.id);
    if (!word || !['der', 'die', 'das'].includes(data.answer)) return;
    const ok = word.art === data.answer;
    updateMastery(vocabKey(word), ok ? 2 : 0);
    if (!ok) recordMistake({ type: 'articles', topic: word.topic, prompt: 'Article: ' + word.de, userAnswer: data.answer, correctAnswer: word.art, explanation: word.art + ' ' + word.de + ' = ' + word.en, sourceId: vocabKey(word) });
    announceCourseState();
  }
});
window.addEventListener('hashchange', () => {
  if (window.parent !== window) window.parent.postMessage({ source: 'german-course', type: 'navigate', module: (location.hash || '#/home').slice(2).split('?')[0] }, window.location.origin);
});

const baseProgressView = viewProgress;
viewProgress = function (el) {
  baseProgressView(el);
  const activity = S.practiceActivity || {};
  const days = Array.from({ length: 7 }, (_, i) => localStudyDate(new Date(Date.now() - (6 - i) * 86400000)));
  const history = Object.entries(activity).sort(([a], [b]) => b.localeCompare(a)).slice(0, 14);
  const section = document.createElement('section');
  section.className = 'activity-report';
  section.innerHTML = '<h3>Practice history</h3><div class="activity-week">' + days.map(day => '<div><strong>' + (activity[day]?.answers || 0) + '</strong><span>' + esc(day.slice(5)) + '</span></div>').join('') + '</div>' +
    (history.length ? '<table><thead><tr><th>Date</th><th>Answers</th><th>Correct</th><th>Accuracy</th></tr></thead><tbody>' + history.map(([day, stat]) => '<tr><td>' + esc(day) + '</td><td>' + stat.answers + '</td><td>' + stat.correct + '</td><td>' + pct(stat.correct, stat.answers) + '%</td></tr>').join('') + '</tbody></table>' : '<p class="sub">No practice recorded yet.</p>');
  el.insertBefore(section, el.children[2] || null);
};

/* Prevent delayed exercise transitions from writing into another module. */
function safeExerciseTransition(callback, milliseconds, expectedRoute) {
  setTimeout(() => { if (S.lastView === expectedRoute) callback(); }, milliseconds);
}

if (window.parent !== window) document.documentElement.classList.add('embedded-course');
setTimeout(announceCourseState, 60);
/* ===== Sync bridge (protocol v1): courseReady, loadState, stateChange ===== */
const COURSE_PROTOCOL = 'course-state-v5/bridge-1';
const STATE_CHANGE_DELAY = 400;
const REQUIRED_OBJECT_KEYS = ['known', 'bookmarked', 'quizStats', 'grammarDone', 'mastery', 'mistakes', 'streak', 'studyTime', 'achievements', 'settings'];
const SYSTEM_EVENT_KEY = 'sprachtreppe-system-event';
let lastAppliedStateVersion = -1;
let stateChangeTimer = 0;
let pendingHint = null;
let stateBaseline = {};

function courseUuid() {
  if (window.crypto && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
  return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
}
function cloneState() { return JSON.parse(JSON.stringify(S)); }
function captureBaseline() { stateBaseline = {}; Object.keys(S).forEach(k => { if (k !== 'lastView') stateBaseline[k] = JSON.stringify(S[k]); }); }
function changedStateKeys() {
  const keys = new Set([...Object.keys(S), ...Object.keys(stateBaseline)]);
  keys.delete('lastView');
  return [...keys].filter(k => JSON.stringify(S[k]) !== stateBaseline[k]);
}
function isPlainObject(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }
function isCompatibleState(state) {
  if (!isPlainObject(state)) return false;
  if (!REQUIRED_OBJECT_KEYS.every(k => isPlainObject(state[k]))) return false;
  if (state.sessionHistory !== undefined && !Array.isArray(state.sessionHistory)) return false;
  if (state.practiceActivity !== undefined && !isPlainObject(state.practiceActivity)) return false;
  if (state.settings.lang !== undefined && !['en', 'gu'].includes(state.settings.lang)) return false;
  return Object.values(state.mastery).every(m => isPlainObject(m) && typeof m.status === 'string');
}
function localStateTimestamp() {
  let max = 0;
  Object.values(S.mastery || {}).forEach(m => { if (typeof m.lastSeen === 'number' && m.lastSeen > max) max = m.lastSeen; });
  Object.values(S.mistakes || {}).forEach(m => { if (typeof m.lastSeen === 'number' && m.lastSeen > max) max = m.lastSeen; });
  Object.values(S.achievements || {}).forEach(v => { if (typeof v === 'number' && v > max) max = v; });
  return max || null;
}
function postToShell(message) { if (window.parent !== window) window.parent.postMessage(message, window.location.origin); }
function hintChange(eventType, entityType, entityId, payload) { pendingHint = { eventType, entityType, entityId: String(entityId), payload: payload || {} }; }

function classifyChange(keys) {
  const has = list => list.some(k => keys.includes(k));
  if (has(['practiceActivity', 'quizStats', 'mistakes', 'sessionHistory'])) return ['answer', 'quiz'];
  if (has(['mastery', 'known'])) return ['mastery', 'vocab'];
  if (has(['grammarDone'])) return ['completion', 'grammar'];
  if (has(['studyTime'])) return ['study_time', 'system'];
  if (has(['settings'])) return ['setting', 'system'];
  return ['completion', 'system'];
}
function emitStateChange(forced) {
  const keys = changedStateKeys();
  if (!keys.length && !forced) { pendingHint = null; return; }
  const [type, entity] = classifyChange(keys);
  const hint = forced || pendingHint || {};
  postToShell({
    source: 'course-engine', type: 'stateChange', clientEventId: courseUuid(), timestamp: new Date().toISOString(),
    eventType: hint.eventType || type, entityType: hint.entityType || entity, entityId: hint.entityId || (keys[0] || 'state'),
    eventPayload: Object.assign({ changedKeys: keys }, hint.payload || {}), snapshot: cloneState()
  });
  pendingHint = null;
  captureBaseline();
}
function scheduleStateChange() { clearTimeout(stateChangeTimer); stateChangeTimer = setTimeout(() => emitStateChange(null), STATE_CHANGE_DELAY); }

const bridgeSave = STORE.save;
STORE.save = function () { bridgeSave(); scheduleStateChange(); };

/* Event hints: wrap global entry points without altering their logic. */
const bridgeUpdateMastery = updateMastery;
updateMastery = function (key, quality) { hintChange('mastery', 'vocab', key, { quality }); return bridgeUpdateMastery.apply(this, arguments); };
const bridgeRecordActivity = recordPracticeActivity;
recordPracticeActivity = function (skill, correct) {
  if (!pendingHint || pendingHint.eventType !== 'mastery') hintChange('answer', skill === 'grammar' ? 'grammar' : skill === 'exam' ? 'exam' : 'quiz', skill, { skill, correct: !!correct });
  else pendingHint.payload = Object.assign({}, pendingHint.payload, { skill, correct: !!correct });

  // Persist every scored answer as an immutable, idempotent event. The course
  // snapshot is still saved locally; this queue survives offline periods and
  // is uploaded separately so two devices' answers are added, not max-merged.
  try {
    const hint = pendingHint || {};
    const mode = skill === 'grammar' || hint.entityType === 'grammar' ? 'grammar' : 'vocabulary';
    const specificId = hint.eventType === 'mastery' ? hint.entityId : '';
    if (window.SP_AUTH && typeof window.SP_AUTH.recordLearningAnswer === 'function') {
      window.SP_AUTH.recordLearningAnswer({
        mode,
        entityType: mode,
        entityId: specificId || String(skill || 'practice'),
        level: S.settings && (S.settings.level || S.settings.currentLevel) || 'All',
        topic: String((hint.payload && hint.payload.topic) || skill || 'general'),
        prompt: specificId || String(hint.entityId || skill || 'Practice'),
        correct: correct === true
      });
    }
  } catch (e) {
    // Local course state and its normal save path must continue even if storage
    // is full or a browser blocks the event queue.
  }
  return bridgeRecordActivity.apply(this, arguments);
};
const bridgeAddStudyTime = addStudyTime;
addStudyTime = function (seconds) { if (!pendingHint) hintChange('study_time', 'system', 'studyTime', { seconds }); return bridgeAddStudyTime.apply(this, arguments); };

/* Called (via prepare-course.py) right before import/reset reloads the page. */
function markSystemEvent(kind) { try { sessionStorage.setItem(SYSTEM_EVENT_KEY, kind); } catch (e) {} }

function applyLoadedState(data) {
  if (data.replaceLocal !== true || typeof data.stateVersion !== 'number' || !Number.isFinite(data.stateVersion) || data.stateVersion < 0) return false;
  if (data.stateVersion < lastAppliedStateVersion) return false;
  if (!isCompatibleState(data.state)) return false;
  const incoming = JSON.parse(JSON.stringify(data.state));
  const fresh = STORE.defaults();
  fresh.settings = Object.assign(STORE.defaults().settings, incoming.settings || {});
  Object.keys(S).forEach(k => { delete S[k]; });
  Object.assign(S, fresh, incoming, { settings: fresh.settings, lastView: S.lastView || incoming.lastView || 'home' });
  lastAppliedStateVersion = data.stateVersion;
  clearTimeout(stateChangeTimer); pendingHint = null;
  originalCourseSave();           // persist via existing STORE without emitting a learning event
  captureBaseline();
  applyTheme(); applySettingsToDOM(); applyLanguage(true);
  announceCourseState();
  return true;
}

window.addEventListener('message', event => {
  if (event.origin !== window.location.origin || event.source !== window.parent) return;
  const data = event.data;
  if (!isPlainObject(data) || data.source !== 'practice-desk' || data.command !== 'loadState') return;
  const accepted = (() => { try { return applyLoadedState(data); } catch (e) { return false; } })();
  postToShell({ source: 'course-engine', type: 'loadStateResult', accepted, stateVersion: typeof data.stateVersion === 'number' ? data.stateVersion : null });
});

function announceReady() {
  let hasLocalState = false;
  try { hasLocalState = !!localStorage.getItem(STORE.key) && isCompatibleState(S); } catch (e) {}
  postToShell({ source: 'course-engine', type: 'courseReady', clientVersion: COURSE_PROTOCOL, hasLocalState, localStateTimestamp: localStateTimestamp() });
  let systemEvent = null;
  try { systemEvent = sessionStorage.getItem(SYSTEM_EVENT_KEY); sessionStorage.removeItem(SYSTEM_EVENT_KEY); } catch (e) {}
  if (systemEvent === 'reset' || systemEvent === 'import') emitStateChange({ eventType: 'reset', entityType: 'system', entityId: systemEvent, payload: { reason: systemEvent } });
}
captureBaseline();
setTimeout(announceReady, 60);
