/*
 * Sprachtreppe — accounts, weekly sync and admin review (client side)
 *
 * SECURITY MODEL (read this):
 *  - There is NO password, key or secret for the admin anywhere in this app. The admin signs in like everyone else;
 *    Supabase Auth stores only a bcrypt hash on the server and enforces rate limits.
 *  - The Supabase "anon" key below is public by design. What a user may read or write is decided by Row-Level-Security
 *    policies in backend/schema.sql — not by hiding screens in this file. A student who edits this JavaScript still
 *    cannot read another student's data or grant himself the admin role.
 *  - The weekly lock is a client-side nudge (the device clock can be tampered with). The authoritative record of who
 *    is overdue is the server-side last_sync_at, which the admin sees.
 */
(function () {
  'use strict';
  const CFG = window.SP_CONFIG || {};
  const enabled = !!(CFG.url && CFG.key);
  window.SP_AUTH = {enabled};
  if (!enabled) return;

  const SYNC_DAYS = CFG.syncDays || 7, WARN_DAYS = CFG.warnDays || 5, DAY = 86400000;
  const K_AUTH = 'sp-auth-v1', K_SYNC = 'sp-sync-v1', K_OWNER = 'sp-owner';
  const ls = {
    get(k) { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
    del(k) { try { localStorage.removeItem(k); } catch (e) {} }
  };
  const E = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  let auth = ls.get(K_AUTH);
  let sync = ls.get(K_SYNC) || {};
  let inflight = null, failedLogins = 0, cooldownUntil = 0, timer = null, syncTimer = null;

  /* ---------------- HTTP ---------------- */
  async function http(path, o) {
    o = o || {};
    const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const to = ctl ? setTimeout(() => ctl.abort(), o.timeout || 15000) : null;
    try {
      const res = await fetch(CFG.url + path, {
        method: o.method || 'GET', signal: ctl && ctl.signal,
        headers: Object.assign({apikey: CFG.key, 'Content-Type': 'application/json', Authorization: 'Bearer ' + (o.token || CFG.key)}, o.headers || {}),
        body: o.body === undefined ? undefined : JSON.stringify(o.body)
      });
      const text = await res.text(); let data = null;
      try { data = text ? JSON.parse(text) : null; } catch (e) {}
      if (!res.ok) {
        const err = new Error((data && (data.error_description || data.msg || data.message || data.error)) || ('HTTP ' + res.status));
        err.status = res.status; err.code = data && (data.error_code || data.code); throw err;
      }
      return {data, date: res.headers && res.headers.get ? res.headers.get('Date') : null};
    } catch (e) {
      if (e.status) throw e;
      const err = new Error('offline'); err.offline = true; throw err;
    } finally { if (to) clearTimeout(to); }
  }
  const online = () => typeof navigator === 'undefined' || navigator.onLine !== false;

  // Merge is monotonic for counters and collections. Array entries are set-unioned,
  // so replaying a snapshot cannot duplicate an answer or study session.
  function mergeLearningStates(remote, local, path) {
    path = path || [];
    if (remote == null) return local == null ? remote : JSON.parse(JSON.stringify(local));
    if (local == null) return JSON.parse(JSON.stringify(remote));
    if (Array.isArray(remote) && Array.isArray(local)) {
      const result = [], seen = new Set();
      for (const item of remote.concat(local)) {
        const stable = value => Array.isArray(value) ? '[' + value.map(stable).join(',') + ']' :
          value && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + stable(value[key])).join(',') + '}' : JSON.stringify(value);
        const id = item && typeof item === 'object' && item.id != null ? 'id:' + item.id : stable(item);
        if (!seen.has(id)) { seen.add(id); result.push(item); }
      }
      return result;
    }
    if (remote && local && typeof remote === 'object' && typeof local === 'object') {
      const result = {};
      for (const key of new Set(Object.keys(remote).concat(Object.keys(local)))) {
        if (!(key in local)) result[key] = remote[key];
        else if (!(key in remote)) result[key] = local[key];
        else result[key] = mergeLearningStates(remote[key], local[key], path.concat(key));
      }
      return result;
    }
    if (typeof remote === 'number' && typeof local === 'number') return Math.max(remote, local);
    if (typeof remote === 'boolean' && typeof local === 'boolean') return remote || local;
    const leaf = path[path.length - 1] || '';
    if (leaf === 'status' && typeof remote === 'string' && typeof local === 'string') {
      const rank = value => ({UNKNOWN:0, NEW:1, WEAK:2, LEARNING:3, FAMILIAR:4, LEARNED:5, STRONG:5, MASTERED:6}[String(value).toUpperCase()] || 0);
      return rank(local) >= rank(remote) ? local : remote;
    }
    if (typeof remote === 'string' && typeof local === 'string' && /(lastSeen|lastStudyDate|updatedAt|completedAt|timestamp|^date$)$/i.test(leaf)) {
      const r = Date.parse(remote), l = Date.parse(local);
      if (Number.isFinite(r) && Number.isFinite(l)) return l >= r ? local : remote;
      const rn = Number(remote), ln = Number(local);
      if (Number.isFinite(rn) && Number.isFinite(ln)) return ln >= rn ? local : remote;
    }
    // Device-local preferences (like language and current page) follow this device.
    return local;
  }

  /* ---------------- idempotent offline answer-event queue ---------------- */
  const K_ANSWER_EVENTS = 'sp-learning-answer-events-v1-';
  let answerSyncTimer = null;
  function answerQueueKey(uid) { return K_ANSWER_EVENTS + String(uid); }
  function readLearningAnswerQueue(uid) {
    const raw = localStorage.getItem(answerQueueKey(uid));
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('Saved offline answer queue is not an array.');
    return parsed.filter(item => item && typeof item === 'object' && typeof item.id === 'string' && item.id);
  }
  function writeLearningAnswerQueue(uid, events) {
    // localStorage writes are atomic. On quota failure, the existing queue is retained
    // and the error propagates instead of silently dropping older offline answers.
    localStorage.setItem(answerQueueKey(uid), JSON.stringify(events));
  }
  function dedupeLearningAnswerQueue(events) {
    const seen = new Set();
    return events.filter(event => {
      const id = String(event && event.id || '');
      if (!id || seen.has(id)) return false;
      seen.add(id); return true;
    }).sort((a, b) => String(a.timestamp || '').localeCompare(String(b.timestamp || '')));
  }
  function recordLearningAnswer(input) {
    const uid = auth && auth.user && auth.user.id;
    if (!uid || !isStudent()) return false;
    input = input || {};
    const entityType = String(input.entityType || input.mode || '').toLowerCase().includes('grammar') ? 'grammar' : 'vocabulary';
    const event = {
      id: (window.crypto && typeof crypto.randomUUID === 'function')
        ? crypto.randomUUID() : Date.now().toString(36) + '-' + Math.random().toString(36).slice(2) + '-' + Math.random().toString(36).slice(2),
      type: 'answer',
      entityType,
      entityId: String(input.entityId || input.topic || input.skill || input.mode || 'practice').trim().slice(0, 160),
      timestamp: new Date().toISOString(),
      mode: String(input.mode || 'practice').slice(0, 40),
      level: String(input.level || 'All').slice(0, 10),
      topic: String(input.topic || '').slice(0, 80),
      prompt: String(input.prompt || '').slice(0, 180),
      answer: String(input.answer || '').slice(0, 120),
      expected: String(input.expected || '').slice(0, 120),
      correct: input.correct === true
    };
    try {
      const queued = readLearningAnswerQueue(uid);
      queued.push(event);
      writeLearningAnswerQueue(uid, dedupeLearningAnswerQueue(queued));
    } catch (error) {
      sync.lastError = 'local-learning-queue'; ls.set(K_SYNC, sync);
      toast('Could not add this answer to the offline sync queue. Connect to the internet and retry sync.');
      return false;
    }
    if (online()) scheduleAnswerSync();
    return true;
  }
  function pendingLearningAnswerCount() {
    try { return readLearningAnswerQueue(auth && auth.user && auth.user.id).length; }
    catch (e) { return -1; }
  }
  function scheduleAnswerSync() {
    clearTimeout(answerSyncTimer);
    answerSyncTimer = setTimeout(() => {
      if (online() && isStudent() && auth && auth.profile && auth.profile.approved) {
        syncNow(false).catch(() => {});
      }
    }, 1800);
  }
  async function syncLearningAnswerEvents(accessToken) {
    const uid = auth && auth.user && auth.user.id;
    if (!uid || !isStudent()) return {pending: 0};
    clearTimeout(answerSyncTimer);
    const pending = dedupeLearningAnswerQueue(readLearningAnswerQueue(uid));
    for (let offset = 0; offset < pending.length; offset += 200) {
      const batch = pending.slice(offset, offset + 200);
      const response = await http('/rest/v1/rpc/sync_learning_answer_events', {
        method: 'POST', token: accessToken, body: {p_events: batch}
      });
      const returned = response.data && response.data.accepted_ids;
      // Older compatible RPCs may not return accepted_ids; a successful batch
      // response itself is an acknowledgement because server inserts are idempotent.
      const acknowledged = new Set(Array.isArray(returned)
        ? returned.map(String)
        : batch.map(item => String(item.id)));
      const stillQueued = readLearningAnswerQueue(uid).filter(item => !acknowledged.has(String(item.id)));
      writeLearningAnswerQueue(uid, stillQueued);
    }
    const remaining = readLearningAnswerQueue(uid).length;
    if (remaining === 0) clearTimeout(answerSyncTimer);
    return {pending: remaining};
  }

  function normaliseCourseSessions(sessions) {
    return (Array.isArray(sessions) ? sessions : []).filter(item => item && typeof item === 'object').map(item => {
      const session = Object.assign({}, item);
      if (!session.id) {
        // Stable fallback for legacy records made before session IDs existed.
        // Newer local records keep their ID; matching this legacy key allows
        // old JSON snapshots to migrate without manufacturing a new session
        // every time a different device signs in.
        const day = String(session.date || session.day || session.completedAt || '').slice(0, 10);
        const mode = String(session.mode || session.skill || 'Web course').slice(0, 50);
        const level = String(session.level || 'All').slice(0, 10);
        const questions = Math.max(0, Number(session.questions || session.total) || 0);
        const correct = Math.max(0, Math.min(questions, Number(session.correct) || 0));
        const duration = Math.max(0, Number(session.duration || session.durationSeconds) || 0);
        session.id = ['web-session', day, mode, level, questions, correct, duration].map(encodeURIComponent).join(':');
      }
      return session;
    });
  }
  function importFlutterSessions(sessions) {
    return (Array.isArray(sessions) ? sessions : []).filter(item => item && typeof item === 'object').map(item => {
      const timestamp = Date.parse(String(item.completedAt || ''));
      const date = new Date(Number.isFinite(timestamp) ? timestamp : Date.now());
      const day = date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
      return {
        id: 'flutter-session:' + String(item.id || (day + ':' + (item.total || 0) + ':' + (item.correct || 0))),
        date: day,
        mode: String(item.mode || 'Flutter practice'),
        level: String(item.level || 'All'),
        questions: Math.max(0, Number(item.total) || 0),
        correct: Math.max(0, Math.min(Number(item.total) || 0, Number(item.correct) || 0)),
        duration: Math.max(0, Number(item.durationSeconds || item.duration) || 0),
        source: 'flutter'
      };
    }).filter(item => item.questions > 0);
  }

  async function syncLearningState(accessToken) {
    const local = JSON.parse(JSON.stringify(S));
    delete local.lastView; // navigation is not learning progress
    delete local.flutter;  // Flutter's normalized answer ledger/aggregates stay server-owned
    local.sessionHistory = normaliseCourseSessions(local.sessionHistory);
    const response = await http('/rest/v1/rpc/sync_learning_state', {
      method: 'POST', token: accessToken, body: {p_state: local}
    });
    const serverState = response.data && response.data.state;
    if (!serverState || typeof serverState !== 'object' || Array.isArray(serverState)) {
      throw new Error('The server returned an invalid learning-state snapshot.');
    }
    const courseState = JSON.parse(JSON.stringify(serverState));
    const flutter = courseState.flutter && typeof courseState.flutter === 'object' ? courseState.flutter : {};
    const flutterSessions = importFlutterSessions(flutter.sessions);
    delete courseState.flutter; // do not copy Flutter's server aggregates into the legacy course state
    const serverHistory = normaliseCourseSessions(courseState.sessionHistory);
    const mergedHistory = mergeLearningStates(serverHistory, local.sessionHistory || []);
    const merged = mergeLearningStates(courseState, local);
    merged.sessionHistory = mergeLearningStates(mergedHistory, flutterSessions);

    // Persist sessions imported from Flutter into the common history as well.
    // This is only sent when the first RPC did not already include those IDs.
    const storedIds = new Set(serverHistory.map(session => String(session.id || '')));
    const needsSessionBackfill = flutterSessions.some(session => !storedIds.has(String(session.id)));
    let finalRevision = response.data.revision || 0;
    let finalUpdatedAt = response.data.updated_at || null;
    if (needsSessionBackfill) {
      const backfill = await http('/rest/v1/rpc/sync_learning_state', {
        method: 'POST', token: accessToken, body: {p_state: {sessionHistory: merged.sessionHistory}}
      });
      if (!backfill.data || !backfill.data.state || typeof backfill.data.state !== 'object') {
        throw new Error('The server did not confirm the merged study history.');
      }
      finalRevision = backfill.data.revision || finalRevision;
      finalUpdatedAt = backfill.data.updated_at || finalUpdatedAt;
    }

    if (typeof applyLoadedState === 'function') {
      if (!applyLoadedState({replaceLocal: true, stateVersion: Date.now(), state: merged})) {
        throw new Error('The saved learning state was not compatible with this course version.');
      }
    } else {
      Object.keys(S).forEach(key => { delete S[key]; });
      Object.assign(S, merged);
      STORE.save();
    }
    return {revision: finalRevision, updated_at: finalUpdatedAt};
  }

  /* ---------------- session ---------------- */
  function saveAuth() { ls.set(K_AUTH, auth); }
  function setSession(s) {
    auth = Object.assign({}, auth || {}, {
      access_token: s.access_token, refresh_token: s.refresh_token,
      expires_at: s.expires_at || Math.floor(Date.now() / 1000) + (s.expires_in || 3600),
      user: {id: s.user.id, email: s.user.email}
    });
    saveAuth();
  }
  async function token() {
    if (!auth || !auth.access_token) throw Object.assign(new Error('not signed in'), {status: 401});
    if (auth.expires_at - 60 > Date.now() / 1000) return auth.access_token;
    const r = await http('/auth/v1/token?grant_type=refresh_token', {method: 'POST', body: {refresh_token: auth.refresh_token}});
    setSession(r.data); return auth.access_token;
  }
  async function loadProfile() {
    const t = await token();
    const r = await http('/rest/v1/profiles?id=eq.' + encodeURIComponent(auth.user.id) + '&select=id,email,full_name,role,approved', {token: t});
    const p = r.data && r.data[0];
    if (!p) throw Object.assign(new Error('profile missing'), {status: 404});
    auth.profile = p; saveAuth(); return p;
  }
  const isAdmin = () => !!(auth && auth.profile && auth.profile.role === 'admin' && auth.profile.approved);
  const isTeacher = () => !!(auth && auth.profile && auth.profile.role === 'teacher' && auth.profile.approved);
  const isStudent = () => !!(auth && auth.profile && auth.profile.role === 'student');

  function adoptUser(uid) {      // every account keeps its own progress on a shared device
    const owner = localStorage.getItem(K_OWNER), key = STORE.key;
    if (owner === uid) return false;
    if (owner) {
      const cur = localStorage.getItem(key); if (cur) localStorage.setItem(key + '@' + owner, cur);
      const mine = localStorage.getItem(key + '@' + uid);
      if (mine) localStorage.setItem(key, mine); else localStorage.removeItem(key);
      localStorage.setItem(K_OWNER, uid); location.reload(); return true;
    }
    localStorage.setItem(K_OWNER, uid); return false;      // first account on this device inherits existing local progress
  }
  async function signOut(returnToLogin = true) {
    try { if (auth && auth.access_token && online()) await http('/auth/v1/logout', {method: 'POST', token: auth.access_token, timeout: 5000}); } catch (e) {}
    auth = null; ls.del(K_AUTH); stopServices();
    if (returnToLogin) showLogin();
  }

  /* ---------------- weekly clock ---------------- */
  function touchClock(first) {
    const now = Date.now();
    if (sync.hw && now < sync.hw - 5 * 60000) sync.clockRewinds = (sync.clockRewinds || 0) + 1;   // device clock moved backwards
    sync.hw = Math.max(sync.hw || 0, now);
    if (!sync.lastSyncLocal) sync.lastSyncLocal = sync.hw;                                         // start of the first weekly cycle
    ls.set(K_SYNC, sync);
  }
  function lockState() {
    if (!isStudent()) return {locked: false, days: 0, left: SYNC_DAYS};
    const hw = Math.max(sync.hw || 0, Date.now());
    const days = (hw - (sync.lastSyncLocal || hw)) / DAY;
    return {locked: days >= SYNC_DAYS, warn: days >= WARN_DAYS, days, left: Math.max(0, SYNC_DAYS - days)};
  }

  /* ---------------- snapshot sent to the teacher ---------------- */
  function trunc(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) : s; }
  function buildSnapshot() {
    const act = S.practiceActivity || {};
    const days = Object.keys(act).sort().slice(-28);
    let a7 = 0, c7 = 0, d7 = 0, aAll = 0, cAll = 0;
    Object.keys(act).forEach(d => { aAll += act[d].answers || 0; cAll += act[d].correct || 0; });
    days.slice(-7).forEach(d => { a7 += act[d].answers || 0; c7 += act[d].correct || 0; if (act[d].answers) d7++; });
    const mastery = S.mastery || {}, status = {};
    Object.values(mastery).forEach(m => { status[m.status] = (status[m.status] || 0) + 1; });
    const skills = {};
    Object.entries(S.quizStats || {}).forEach(([k, v]) => { skills[k] = {done: v.done | 0, correct: v.correct | 0}; });
    const grammar = {};
    Object.entries(S.gstats || {}).forEach(([k, v]) => { grammar[k] = {n: v.n | 0, ok: v.ok | 0}; });
    const mistakes = Object.values(S.mistakes || {}).sort((a, b) => (b.count | 0) - (a.count | 0)).slice(0, 25)
      .map(m => ({type: trunc(m.type, 30), topic: trunc(m.topic, 60), prompt: trunc(m.prompt, 240), you: trunc(m.userAnswer, 120), correct: trunc(m.correctAnswer, 120), count: m.count | 0}));
    const writing = (S.writingLog || []).slice(-15).map(w => ({t: w.t, level: w.level, title: trunc(w.title, 80), score: w.score | 0, words: w.words | 0, text: trunc(w.text, 2500)}));
    const ownerId = (auth && auth.user && auth.user.id) || (auth && auth.profile && auth.profile.id) || '';
    const queuedKey = 'sp_task_submissions_v1_' + ownerId;
    const rawQueued = ownerId ? ls.get(queuedKey) : [];
    const queued = Array.isArray(rawQueued) ? rawQueued : [];
    // Sync a bounded batch so a long offline period cannot exceed the server payload limit.
    const toSend = queued.slice(0, 80);
    syncedTaskSubmissionIds = toSend.map(item => String(item && item.id || '')).filter(Boolean);
    const queuedWriting = toSend.map(item => ({
      t: item.t || new Date().toISOString(), level: trunc(item.level || '', 10),
      title: trunc(item.title || 'Assignment response', 80), score: item.score | 0,
      words: item.words | 0, text: trunc(item.text || '', 2500),
      assignment_id: trunc(item.assignment_id || '', 80), client_id: trunc(item.client_id || item.id || '', 80),
      kind: 'assignment'
    }));
    const rawTaskProgress = ownerId ? ls.get('sp_task_progress_v1_' + ownerId) : {};
    const taskProgress = rawTaskProgress && typeof rawTaskProgress === 'object' && !Array.isArray(rawTaskProgress) ? rawTaskProgress : {};
    const assignment_progress = Object.values(taskProgress).slice(-100).map(item => ({
      assignment_id: trunc(item.assignment_id || '', 80), title: trunc(item.title || 'Assignment', 80),
      skill: trunc(item.skill || 'mixed', 30), done: Math.max(0, item.done | 0),
      correct: Math.max(0, item.correct | 0), target_count: Math.max(0, item.target_count | 0),
      submitted: !!item.submitted, completed: !!item.completed, updated_at: item.updated_at || null
    }));
    const sessions = (S.sessionHistory || []).slice(-30).map(s => ({date: s.date, q: s.questions | 0, ok: s.correct | 0, sec: s.duration | 0}));
    const activity = {}; days.forEach(d => { activity[d] = {a: act[d].answers | 0, c: act[d].correct | 0}; });
    const summary = {
      v: 1, app: window.__SP_ENGINE_VERSION || '', device_time: new Date().toISOString(),
      answers_total: aAll, correct_total: cAll, answers_7d: a7, correct_7d: c7, active_days_7d: d7,
      streak: (S.streak && S.streak.current) | 0, longest_streak: (S.streak && S.streak.longest) | 0,
      study_seconds_total: (S.studyTime && S.studyTime.total) | 0, study_seconds_week: (S.studyTime && S.studyTime.week) | 0, sessions: (S.studyTime && S.studyTime.sessions) | 0,
      words_known: Object.keys(S.known || {}).length, words_seen: Object.keys(mastery).length, mastery: status,
      skills, grammar, clock_rewinds: sync.clockRewinds | 0, clock_skew_min: sync.skewMin | 0
    };
    return {summary, mistakes, writing: writing.concat(queuedWriting), sessions, activity, assignment_progress};
  }
  const newId = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : (Date.now().toString(36) + Math.random().toString(36).slice(2, 12));

  /* ---------------- sync ---------------- */
  let syncedTaskSubmissionIds = [];

  async function syncNow(manual) {
    if (inflight) return inflight;
    inflight = (async () => {
      sync.lastAttempt = Date.now(); ls.set(K_SYNC, sync);
      if (!isStudent()) return {skipped: 'admin'};
      try {
        if (!auth.profile.approved) { await loadProfile(); if (!auth.profile.approved) { renderChip(); return {pending: true}; } }
        const t = await token();
        await syncLearningAnswerEvents(t); // immutable answer events are deduplicated server-side by ID
        await syncLearningState(t); // pull + merge personal learning state before producing the teacher report
        const snapshot = buildSnapshot();
        const r = await http('/rest/v1/rpc/submit_progress', {method: 'POST', token: t, body: {p_payload: snapshot, p_client_id: newId()}});
        // Remove only the local task responses included in this server-accepted snapshot.
        if (syncedTaskSubmissionIds.length && auth && auth.user && auth.user.id) {
          const queueKey = 'sp_task_submissions_v1_' + auth.user.id;
          const included = new Set(syncedTaskSubmissionIds);
          const rawPending = ls.get(queueKey);
          const pending = Array.isArray(rawPending) ? rawPending : [];
          const remaining = pending.filter(item => !included.has(String(item && item.id || '')));
          ls.set(queueKey, remaining);
          syncedTaskSubmissionIds = [];
          if (remaining.length) setTimeout(() => { if (online() && auth && isStudent()) syncNow(false).catch(() => {}); }, 1200);
        }
        const now = Date.now(), hw = Math.max(sync.hw || 0, now);
        sync.hw = hw; sync.lastSyncLocal = hw; sync.lastOk = now; sync.lastError = null;
        sync.lastSyncServer = r.data && r.data.server_time;
        if (sync.lastSyncServer) { sync.skewMin = Math.round((Date.parse(sync.lastSyncServer) - now) / 60000); }
        const fb = (r.data && r.data.feedback) || [];
        if (fb.length) {
          sync.feedback = fb.concat(sync.feedback || []).slice(0, 20);
          toast('Your teacher reviewed your progress — see Account.');
          try { await http('/rest/v1/rpc/ack_feedback', {method: 'POST', token: t, body: {p_ids: fb.map(x => x.id)}}); } catch (e) {}
        }
        ls.set(K_SYNC, sync); renderLock(); renderChip();
        if (pendingLearningAnswerCount() > 0) scheduleAnswerSync();
        return {ok: true};
      } catch (e) {
        sync.lastError = e.offline ? 'offline' : trunc(e.message, 160); ls.set(K_SYNC, sync);
        if (e.status === 401 || e.status === 400 && /refresh|token/i.test(e.message)) { /* session no longer valid */ auth.access_token = null; saveAuth(); renderLock(); }
        if (!manual && !e.offline) console.warn('sync failed:', e.message);
        renderChip();
        throw e;
      }
    })().finally(() => { inflight = null; });
    return inflight;
  }
  function markDirty() {
    if (!isStudent() || !auth.profile.approved) return;
    sync.dirty = true; clearTimeout(syncTimer);
    syncTimer = setTimeout(() => { if (online() && Date.now() - (sync.lastAttempt || 0) > 10 * 60000) syncNow(false).catch(() => {}); }, 120000);
  }

  /* ---------------- UI helpers ---------------- */
  function css() {
    if (document.getElementById('spCss')) return;
    const st = document.createElement('style'); st.id = 'spCss';
    st.textContent = `
      body.sp-locked > *:not(#spAuth):not(#spLock):not(#spToast){visibility:hidden}
      #spAuth,#spLock{position:fixed;inset:0;z-index:9999;background:var(--bg);color:var(--text);display:flex;align-items:center;justify-content:center;padding:18px;overflow:auto}
      .sp-card{width:min(420px,100%);background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px;box-shadow:var(--shadow)}
      .sp-card h2{margin:0 0 4px}.sp-card label{display:block;font-size:12.5px;font-weight:700;margin:12px 0 4px}
      .sp-card input,.sp-card select,.sp-card textarea{width:100%;padding:12px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--text);font:inherit}
      .sp-tabs{display:flex;gap:6px;margin:12px 0}.sp-tabs button{flex:1}
      .sp-err{color:var(--warn);font-size:13px;margin-top:10px;min-height:18px}.sp-ok{color:var(--ok)}
      #spToast{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:var(--text);color:var(--bg);padding:10px 16px;border-radius:10px;z-index:10000;font-size:13.5px;max-width:90vw}
      #spChip{font-size:11.5px;font-weight:700;padding:4px 8px;border-radius:99px;border:1px solid var(--line);color:var(--muted);white-space:nowrap}
      #spChip.warn{color:var(--gold);border-color:var(--gold)}#spChip.bad{color:var(--warn);border-color:var(--warn)}
      .sp-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px;margin:10px 0}
      .sp-stat{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:10px}.sp-stat b{display:block;font-size:20px}
      .sp-table{width:100%;border-collapse:collapse;font-size:13px}.sp-table th,.sp-table td{padding:8px 6px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
      .sp-badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11.5px;font-weight:700;border:1px solid var(--line)}
      .sp-badge.bad{color:var(--warn);border-color:var(--warn)}.sp-badge.ok{color:var(--ok);border-color:var(--ok)}.sp-badge.warn{color:var(--gold);border-color:var(--gold)}
      .sp-pre{white-space:pre-wrap;background:var(--bg);border-left:3px solid var(--accent2);padding:8px 10px;border-radius:6px;font-size:13px}`;
    document.head.appendChild(st);
  }
  function toast(msg) {
    let t = document.getElementById('spToast'); if (!t) { t = document.createElement('div'); t.id = 'spToast'; document.body.appendChild(t); }
    t.textContent = msg; t.style.display = 'block'; clearTimeout(t._h); t._h = setTimeout(() => { t.style.display = 'none'; }, 5000);
  }
  const fmtAgo = iso => {
    if (!iso) return 'never';
    const d = (Date.now() - Date.parse(iso)) / 3600000;
    return d < 1 ? 'just now' : d < 48 ? Math.round(d) + ' h ago' : Math.round(d / 24) + ' days ago';
  };
  const fmtMin = s => Math.round((s || 0) / 60) + ' min';
  const pctOf = (a, b) => b ? Math.round(100 * a / b) + '%' : '–';

  /* ---------------- passwordless email OTP authentication ---------------- */
  async function sendCode(email, allowNewStudent = false, fullName = '') {
    const body = {email: String(email).trim(), create_user: !!allowNewStudent};
    if (allowNewStudent) body.data = {full_name: String(fullName || '').trim().slice(0, 80)};
    try {
      // Only Student → Create account can request creation of a new Auth user.
      await http('/auth/v1/otp', {method: 'POST', body});
    } catch (e) {
      // Keep account-existence details private; surface rate limits/provider errors.
      if (e.offline || e.status === 429 || e.status >= 500) throw e;
    }
  }

  async function verifyCode(email, code) {
    const r = await http('/auth/v1/verify', {
      method: 'POST',
      body: {type: 'email', email: String(email).trim(), token: String(code).replace(/\s+/g, '')}
    });
    auth = null; setSession(r.data);
    const profile = await loadProfile();
    if (!sync.uid || sync.uid !== auth.user.id) sync = {uid: auth.user.id};
    touchClock(true); ls.set(K_SYNC, sync);
    return profile;
  }

  function showLogin(msg) {
    css(); document.body.classList.add('sp-locked');
    let box = document.getElementById('spAuth'); if (box) box.remove();
    const oldLock = document.getElementById('spLock'); if (oldLock) oldLock.remove();
    box = document.createElement('div'); box.id = 'spAuth';
    let mode = 'in', who = 'student', codeSent = false, resendAt = 0;

    const setErr = (message, ok) => {
      const el = box.querySelector('#spErr');
      if (el) { el.textContent = message; el.className = 'sp-err' + (ok ? ' sp-ok' : ''); }
    };
    const draw = () => {
      const creatingStudent = who === 'student' && mode === 'up';
      box.innerHTML = '<form class="sp-card" id="spForm" autocomplete="on" novalidate>' +
        '<h2>🇩🇪 Sprachtreppe</h2>' +
        '<div class="mini-muted">' + (who === 'admin' ? 'Teacher / admin access' : creatingStudent ? 'Create a student account' : 'Student sign-in') + '</div>' +
        '<div class="sp-tabs">' +
        '<button type="button" class="btn small ' + (who === 'student' ? '' : 'ghost') + '" data-who="student">Student</button>' +
        '<button type="button" class="btn small ' + (who === 'admin' ? '' : 'ghost') + '" data-who="admin">Admin</button></div>' +
        (creatingStudent ? '<label for="spName">Full name</label><input id="spName" autocomplete="name" maxlength="80" required>' : '') +
        '<label for="spEmail">Email</label><input id="spEmail" type="email" inputmode="email" autocomplete="email" required ' + (codeSent ? 'disabled' : '') + '>' +
        (codeSent ? '<label for="spCode">6-digit email code</label><input id="spCode" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required>' : '') +
        '<div class="sp-err" id="spErr" role="alert">' + E(msg || '') + '</div>' +
        '<button class="btn" style="width:100%;margin-top:6px" type="submit">' + (codeSent ? 'Verify code' : creatingStudent ? 'Send registration code' : 'Send 6-digit code') + '</button>' +
        '<div style="display:flex;justify-content:space-between;margin-top:12px;font-size:13px;gap:10px">' +
        (who === 'student' ? '<a href="#" id="spSwitch">' + (mode === 'up' ? 'I already have an account' : 'Create account') + '</a>' : '<span>Only approved teachers and administrators can continue.</span>') +
        (codeSent ? '<a href="#" id="spResend">Send a new code</a>' : '<span></span>') + '</div>' +
        '<div class="mini-muted" style="margin-top:12px">Sign-in uses a one-time email code. New student accounts stay pending until an administrator approves them. Internet is needed to sign in and to sync progress each week.</div>' +
        '</form>';

      box.querySelectorAll('[data-who]').forEach(b => b.onclick = () => {
        who = b.dataset.who; mode = 'in'; codeSent = false; msg = ''; draw();
      });
      const sw = box.querySelector('#spSwitch');
      if (sw) sw.onclick = e => { e.preventDefault(); mode = mode === 'up' ? 'in' : 'up'; codeSent = false; msg = ''; draw(); };

      const rs = box.querySelector('#spResend');
      if (rs) rs.onclick = async e => {
        e.preventDefault();
        const waitMs = resendAt - Date.now();
        if (waitMs > 0) { setErr('Wait ' + Math.ceil(waitMs / 1000) + ' seconds before requesting another code.'); return; }
        const email = box.querySelector('#spEmail').value.trim();
        const name = (box.querySelector('#spName') || {}).value || '';
        try {
          await sendCode(email, who === 'student' && mode === 'up', name);
          resendAt = Date.now() + 60000;
          setErr('If this email is eligible, a new 6-digit code was sent. Check inbox and spam.', true);
        } catch (e2) {
          setErr(e2.offline ? 'No internet connection.' : e2.status === 429 ? 'Too many requests. Wait at least 60 seconds before retrying.' : 'Could not send the code. Check email settings and retry.');
        }
      };
      box.querySelector('#spForm').onsubmit = submit;
    };

    const submit = async ev => {
      ev.preventDefault();
      const email = box.querySelector('#spEmail').value.trim();
      const creatingStudent = who === 'student' && mode === 'up';
      const name = ((box.querySelector('#spName') || {}).value || '').trim();
      if (Date.now() < cooldownUntil) { setErr('Too many attempts. Wait ' + Math.ceil((cooldownUntil - Date.now()) / 1000) + ' seconds.'); return; }
      if (!/^\S+@\S+\.\S+$/.test(email)) { setErr('Enter a valid email address.'); return; }
      if (creatingStudent && !name) { setErr('Enter your full name.'); return; }

      const btn = box.querySelector('button[type=submit]');
      if (!codeSent) {
        btn.disabled = true;
        try {
          await sendCode(email, creatingStudent, name);
          codeSent = true; resendAt = Date.now() + 60000; msg = ''; draw();
          const em = box.querySelector('#spEmail'); if (em) em.value = email;
          const nm = box.querySelector('#spName'); if (nm) nm.value = name;
          setErr('If this email is eligible, a 6-digit code was sent. Check inbox and spam.', true);
        } catch (e) {
          setErr(e.offline ? 'No internet connection.' : e.status === 429 ? 'Too many email requests. Wait at least 60 seconds.' : 'Could not send the code. Check email settings and try again.');
          btn.disabled = false;
        }
        return;
      }

      const code = (box.querySelector('#spCode') || {}).value || '';
      if (!/^\d{6}$/.test(code.trim())) { setErr('Enter the 6-digit code from the email.'); return; }
      btn.disabled = true;
      try {
        const profile = await verifyCode(email, code);
        if (creatingStudent) {
          if (profile.role !== 'student' || profile.approved) {
            await signOut(false);
            setErr('This email already belongs to an account. Choose Student → Sign in instead.');
            btn.disabled = false; return;
          }
          await http('/rest/v1/rpc/complete_student_signup', {
            method: 'POST', token: await token(), body: {p_full_name: name}
          });
          await signOut(false);
          mode = 'in'; who = 'student'; codeSent = false;
          msg = 'Account created. An administrator must approve it before you can sign in.';
          draw();
          const em = box.querySelector('#spEmail'); if (em) em.value = email;
          setErr(msg, true);
          return;
        }

        if (!profile.approved) {
          await signOut(false);
          setErr('Your account is waiting for administrator approval. Please try again after approval.');
          btn.disabled = false; return;
        }
        if (who === 'admin' && !['teacher', 'admin'].includes(profile.role)) {
          await signOut(false);
          setErr('This account is not an administrator or approved teacher account. Ask an administrator to approve or promote it.');
          btn.disabled = false; return;
        }
        if (who === 'student' && profile.role !== 'student') {
          await signOut(false);
          setErr('This account has staff access. Use the Admin tab.');
          btn.disabled = false; return;
        }
        failedLogins = 0;
        await finishLogin(profile);
      } catch (e) {
        if (!e.offline) { failedLogins++; if (failedLogins >= 5) { cooldownUntil = Date.now() + 30000; failedLogins = 0; } }
        if (auth && auth.access_token) await signOut(false);
        setErr(e.offline ? 'No internet connection. Sign-in needs internet.' : e.status === 429 ? 'Too many attempts — try again later.' : [400, 403].includes(e.status) && /token|otp|code/i.test(e.message || '') ? 'Invalid or expired code.' : (e.message && /student registration is unavailable/i.test(e.message)) ? 'This account cannot use registration. Try Student → Sign in.' : 'Could not complete sign-in. Check the code, approval status, and try again.');
        btn.disabled = false;
      }
    };

    document.body.appendChild(box); draw();
  }

    async function finishLogin(prof) {
    if (adoptUser(auth.user.id)) return;
    const b = document.getElementById('spAuth'); if (b) b.remove();
    document.body.classList.remove('sp-locked');
    startServices();
    // Land each approved role on its matching Flutter-style home screen after OTP unlock.
    if (location.hash === '#/home') {
      if ((isAdmin() || isTeacher()) && typeof window.viewFlutterDashboard === 'function') {
        location.hash = '#/dashboard';
      } else if (typeof window.viewFlutterHome === 'function') {
        const courseView = document.getElementById('view');
        if (courseView) window.viewFlutterHome(courseView);
      }
    }
    if (isStudent() && auth.profile.approved) syncNow(true).catch(() => {});
  }

  /* ---------------- weekly lock screen ---------------- */
  function renderLock() {
    css();
    const st = lockState(), has = !!document.getElementById('spLock');
    if (!isStudent() || !st.locked) { if (has) document.getElementById('spLock').remove(); if (!document.getElementById('spAuth')) document.body.classList.remove('sp-locked'); return; }
    if (has) return;
    document.body.classList.add('sp-locked');
    const box = document.createElement('div'); box.id = 'spLock';
    box.innerHTML = `<div class="sp-card"><h2>📡 Weekly sync needed</h2>
      <p class="mini-muted" style="line-height:1.6">It has been ${Math.floor(st.days)} days since your progress was sent to your teacher. Connect to the internet and tap Sync — everything you studied is kept and will be sent.</p>
      <div class="sp-err" id="spLockMsg" role="alert"></div>
      <button class="btn" id="spLockSync" style="width:100%">Sync now</button>
      <button class="btn ghost" id="spLockOut" style="width:100%;margin-top:8px">Sign out</button></div>`;
    document.body.appendChild(box);
    box.querySelector('#spLockSync').onclick = async () => {
      const m = box.querySelector('#spLockMsg'); m.textContent = 'Syncing…'; m.className = 'sp-err sp-ok';
      try {
        if (!auth.access_token) { signOut(); return; }
        const r = await syncNow(true);
        if (r && r.pending) { m.textContent = 'Your account is not approved yet. Ask your teacher.'; m.className = 'sp-err'; }
      } catch (e) { m.className = 'sp-err'; m.textContent = e.offline ? 'No internet connection yet.' : e.status === 401 ? 'Please sign in again.' : trunc(e.message, 120); if (e.status === 401) signOut(); }
    };
    box.querySelector('#spLockOut').onclick = () => signOut();
  }
  function renderChip() {
    css();
    let c = document.getElementById('spChip');
    if (!c) {
      const hdr = document.querySelector('header'), set = document.getElementById('settingsBtn');
      if (!hdr) return;
      c = document.createElement('span'); c.id = 'spChip'; hdr.insertBefore(c, set);
      const b = document.createElement('button'); b.className = 'iconbtn'; b.id = 'spAcct'; b.title = 'Account'; b.setAttribute('aria-label', 'Account'); b.textContent = '👤';
      b.onclick = () => { location.hash = '#/account'; }; hdr.insertBefore(b, set);
    }
    if (isAdmin()) { c.textContent = 'Admin'; c.className = ''; return; }
    if (isTeacher()) { c.textContent = 'Teacher'; c.className = ''; return; }
    if (!isStudent()) { c.textContent = ''; return; }
    if (!auth.profile.approved) { c.textContent = 'Awaiting approval'; c.className = 'warn'; return; }
    const st = lockState();
    if (sync.lastError && sync.lastError !== 'offline' && st.warn) { c.textContent = 'Sync problem'; c.className = 'bad'; return; }
    c.textContent = st.locked ? 'Sync required' : st.warn ? 'Sync in ' + Math.ceil(st.left) + ' d' : 'Synced ' + (sync.lastOk ? fmtAgo(new Date(sync.lastOk).toISOString()) : 'soon');
    c.className = st.locked ? 'bad' : st.warn ? 'warn' : '';
  }

  /* ---------------- account view ---------------- */
  window.viewAccount = function (el) {
    if (!auth || !auth.profile) { el.innerHTML = '<div class="card">Not signed in.</div>'; return; }
    const p = auth.profile, st = lockState();
    const roleLabel = isAdmin() ? 'Administrator' : isTeacher() ? 'Teacher' : p.approved ? 'Student · approved' : 'Student · waiting for approval';
    const fb = (sync.feedback || []).slice(0, 8);
    el.innerHTML = `<h2>Account</h2>
      <div class="card"><div><b>${E(p.full_name || p.email)}</b></div><div class="mini-muted">${E(p.email)}</div>
        <div style="margin-top:8px"><span class="sp-badge ${p.approved ? "ok" : "warn"}">${E(roleLabel)}</span></div>
        ${isStudent() ? `<p class="mini-muted" style="margin-top:12px;line-height:1.6">Last sent to your teacher: <b>${sync.lastOk ? fmtAgo(new Date(sync.lastOk).toISOString()) : 'not yet'}</b><br>Next sync due within: <b>${Math.ceil(st.left)} days</b> (every ${SYNC_DAYS} days)</p>
        <div class="row"><button class="btn" id="spSyncBtn">🔄 Sync now</button></div><div id="spSyncMsg" class="mt mini-muted">${sync.lastError ? E(sync.lastError === 'offline' ? 'Offline — will retry when connected.' : sync.lastError) : ''}</div>` : ''}
      </div>
      ${fb.length ? `<h3>Teacher feedback</h3><div class="card">${fb.map(f => `<div style="margin-bottom:12px"><span class="sp-badge ${f.status === 'flagged' ? 'bad' : 'ok'}">${E(f.status)}</span> ${f.rating ? '★'.repeat(f.rating | 0) : ''}<div style="margin-top:6px;white-space:pre-wrap">${E(f.note || '(no comment)')}</div></div>`).join('')}</div>` : ''}
      <div class="mini-muted" style="margin-top:12px">Sign-in is passwordless. A one-time code is sent to your email whenever you sign in.</div>
      <div class="row" style="margin-top:16px"><button class="btn ghost" id="spOutBtn">Sign out</button></div>`;
    const sb = el.querySelector('#spSyncBtn');
    if (sb) sb.onclick = async () => { const m = el.querySelector('#spSyncMsg'); m.textContent = 'Syncing…'; try { const r = await syncNow(true); m.textContent = r && r.pending ? 'Waiting for teacher approval.' : 'Sent ✔'; setTimeout(() => window.viewAccount(el), 700); } catch (e) { m.textContent = e.offline ? 'No internet connection.' : trunc(e.message, 120); } };
    el.querySelector('#spOutBtn').onclick = () => { if (confirm('Sign out? You need internet to sign in again.')) signOut(); };
  };

  /* ---------------- admin console ---------------- */
  const adm = {tab: 'all', rows: null, sel: null};
  async function admRpc(name, body) { return (await http('/rest/v1/rpc/' + name, {method: 'POST', token: await token(), body: body || {}})).data; }
  async function admRest(path, o) { o = o || {}; return (await http('/rest/v1/' + path, Object.assign({token: await token()}, o))).data; }
  const overdue = r => r.approved && r.role !== 'admin' && (!r.last_sync_at || Date.now() - Date.parse(r.last_sync_at) > SYNC_DAYS * DAY);
  const csvCell = v => { let s = String(v == null ? '' : v); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"'; };

  window.viewAdmin = async function (el) {
    if (!isAdmin()) { el.innerHTML = '<div class="card">Administrators only.</div>'; return; }
    if (adm.sel) return admStudent(el, adm.sel);
    el.innerHTML = '<h2>🛡️ Admin</h2><div class="card mini-muted">Loading…</div>';
    try { adm.rows = await admRpc('admin_overview'); }
    catch (e) { el.innerHTML = '<h2>🛡️ Admin</h2><div class="card">' + (e.offline ? 'No internet connection.' : E(e.message)) + '</div>'; return; }
    const rows = adm.rows.filter(r => r.role !== 'admin');
    const pending = rows.filter(r => !r.approved), late = rows.filter(overdue), unrev = rows.reduce((a, r) => a + (Number(r.unreviewed) || 0), 0);
    const shown = adm.tab === 'pending' ? pending : adm.tab === 'late' ? late : adm.tab === 'review' ? rows.filter(r => Number(r.unreviewed) > 0) : rows;
    el.innerHTML = `<h2>🛡️ Admin</h2>
      <div class="sp-grid"><div class="sp-stat"><b>${rows.length}</b>students</div><div class="sp-stat"><b>${pending.length}</b>awaiting approval</div><div class="sp-stat"><b>${unrev}</b>to review</div><div class="sp-stat"><b>${late.length}</b>overdue sync</div></div>
      <div class="chipgroup" id="admTabs">${[['all', 'All'], ['pending', 'Approvals'], ['review', 'To review'], ['late', 'Overdue']].map(([k, l]) => `<button data-t="${k}" class="${adm.tab === k ? 'active' : ''}">${l}</button>`).join('')}</div>
      <div class="card" style="overflow-x:auto"><table class="sp-table"><thead><tr><th>Student</th><th>Status</th><th>Last sync</th><th>7-day accuracy</th><th></th></tr></thead><tbody>
      ${shown.length ? shown.map(r => { const s = r.last_summary || {}; return `<tr><td><b>${E(r.full_name || '(no name)')}</b><div class="mini-muted">${E(r.email)}</div></td>
        <td>${r.approved ? '<span class="sp-badge ok">approved</span>' : '<span class="sp-badge warn">pending</span>'} ${overdue(r) ? '<span class="sp-badge bad">overdue</span>' : ''} ${Number(r.unreviewed) ? '<span class="sp-badge warn">' + E(r.unreviewed) + ' new</span>' : ''}</td>
        <td>${E(fmtAgo(r.last_sync_at))}</td><td>${E(pctOf(s.correct_7d, s.answers_7d))} <span class="mini-muted">(${E(s.answers_7d || 0)} answers)</span></td>
        <td><button class="btn tiny" data-open="${E(r.id)}">Open</button></td></tr>`; }).join('') : '<tr><td colspan="5" class="mini-muted">Nothing here.</td></tr>'}
      </tbody></table></div>
      <div class="row"><button class="btn ghost" id="admCsv">⬇ Export CSV</button><button class="btn ghost" id="admRefresh">🔄 Refresh</button></div>`;
    el.querySelectorAll('#admTabs button').forEach(b => b.onclick = () => { adm.tab = b.dataset.t; window.viewAdmin(el); });
    el.querySelectorAll('[data-open]').forEach(b => b.onclick = () => { adm.sel = b.dataset.open; window.viewAdmin(el); });
    el.querySelector('#admRefresh').onclick = () => window.viewAdmin(el);
    el.querySelector('#admCsv').onclick = () => {
      const head = ['name', 'email', 'approved', 'last_sync', 'overdue', 'submissions', 'to_review', 'answers_7d', 'accuracy_7d', 'streak', 'words_known'];
      const lines = [head.join(',')].concat(rows.map(r => { const s = r.last_summary || {}; return [r.full_name, r.email, r.approved, r.last_sync_at || '', overdue(r), r.submissions, r.unreviewed, s.answers_7d || 0, pctOf(s.correct_7d, s.answers_7d), s.streak || 0, s.words_known || 0].map(csvCell).join(','); }));
      const blob = new Blob([lines.join('\n')], {type: 'text/csv'}), a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'sprachtreppe-students.csv'; document.body.appendChild(a); a.click(); a.remove();
    };
  };
  async function admStudent(el, id) {
    const row = (adm.rows || []).find(r => r.id === id) || {};
    el.innerHTML = '<div class="card mini-muted">Loading…</div>';
    let subs = [];
    try { subs = await admRest('submissions?student_id=eq.' + encodeURIComponent(id) + '&select=id,created_at,summary,review_status,review_note,rating&order=created_at.desc&limit=20'); }
    catch (e) { el.innerHTML = '<div class="card">' + (e.offline ? 'No internet connection.' : E(e.message)) + '</div>'; return; }
    const last = subs[0], s = last ? (last.summary || {}) : {};
    let pay = null;
    if (last) { try { const d = await admRest('submissions?id=eq.' + encodeURIComponent(last.id) + '&select=payload'); pay = d[0] && d[0].payload; } catch (e) {} }
    pay = pay || {};
    const skills = Object.assign({}, ...Object.entries(s.grammar || {}).map(([k, v]) => ({['g:' + k]: {done: v.n, correct: v.ok}})), ...Object.entries(s.skills || {}).map(([k, v]) => ({[k]: v})));
    const skillRows = Object.entries(skills).filter(([, v]) => v.done > 0).sort((a, b) => (a[1].correct / a[1].done) - (b[1].correct / b[1].done));
    el.innerHTML = `<div class="row"><button class="btn ghost small" id="admBack">← Students</button></div>
      <h2>${E(row.full_name || row.email || 'Student')}</h2><div class="mini-muted">${E(row.email || '')}</div>
      <div style="margin:10px 0">
        <span class="sp-badge">${row.role === 'teacher' ? 'Teacher' : 'Student'}</span>
        ${row.approved ? '<span class="sp-badge ok">approved</span>' : '<span class="sp-badge warn">pending</span>'}
        ${overdue(row) ? '<span class="sp-badge bad">overdue</span>' : ''}
        <button class="btn tiny" id="admApprove">${row.approved ? 'Disable account' : 'Approve account'}</button>
        ${row.role === 'teacher' ? '<button class="btn tiny ghost" id="admRoleBtn">Return to student</button>' : row.approved && row.role === 'student' ? '<button class="btn tiny ghost" id="admRoleBtn">Promote to teacher</button>' : ''}
      </div>
      ${last ? `<div class="sp-grid">
        <div class="sp-stat"><b>${E(pctOf(s.correct_7d, s.answers_7d))}</b>accuracy (7 d)</div><div class="sp-stat"><b>${E(s.answers_7d | 0)}</b>answers (7 d)</div>
        <div class="sp-stat"><b>${E(s.active_days_7d | 0)}/7</b>active days</div><div class="sp-stat"><b>${E(s.streak | 0)}</b>day streak</div>
        <div class="sp-stat"><b>${E(fmtMin(s.study_seconds_total))}</b>study time</div><div class="sp-stat"><b>${E(s.words_known | 0)}</b>words known</div></div>
        ${s.clock_rewinds ? `<div class="sp-badge bad">device clock moved back ${E(s.clock_rewinds)}×</div>` : ''}
        <h3>Skills (weakest first)</h3><div class="card" style="overflow-x:auto"><table class="sp-table">${skillRows.length ? skillRows.slice(0, 14).map(([k, v]) => `<tr><td>${E(k)}</td><td>${E(pctOf(v.correct, v.done))}</td><td class="mini-muted">${E(v.correct)}/${E(v.done)}</td></tr>`).join('') : '<tr><td class="mini-muted">No data yet.</td></tr>'}</table></div>
        <h3>Frequent mistakes</h3><div class="card">${(pay.mistakes || []).slice(0, 10).map(m => `<div style="margin-bottom:10px"><div class="mini-muted">${E(m.topic)} · ${E(m.count)}×</div><div>${E(m.prompt)}</div><div class="mini-muted">answered “${E(m.you)}” — correct “${E(m.correct)}”</div></div>`).join('') || '<span class="mini-muted">None.</span>'}</div>
        <h3>Writing samples</h3><div class="card">${(pay.writing || []).slice(-4).reverse().map(w => `<div style="margin-bottom:14px"><div><b>${E(w.title)}</b> <span class="sp-badge">${E(w.level)}</span> <span class="sp-badge ${w.score >= 70 ? 'ok' : 'warn'}">${E(w.score)}/100</span> <span class="mini-muted">${E(w.words)} words</span></div><div class="sp-pre">${E(w.text)}</div></div>`).join('') || '<span class="mini-muted">None.</span>'}</div>` : '<div class="card mini-muted">This student has not synced yet.</div>'}
      <h3>Submissions</h3><div id="admSubs">${subs.map(x => `<div class="card" data-sub="${E(x.id)}"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><b>${E(new Date(x.created_at).toLocaleString())}</b><span class="sp-badge ${x.review_status === 'pending' ? 'warn' : x.review_status === 'flagged' ? 'bad' : 'ok'}">${E(x.review_status)}</span></div>
        <div class="mini-muted">${E((x.summary && x.summary.answers_7d) || 0)} answers (7 d) · ${E(pctOf(x.summary && x.summary.correct_7d, x.summary && x.summary.answers_7d))}</div>
        <label class="mini-muted" for="rn-${E(x.id)}">Feedback to student</label><textarea id="rn-${E(x.id)}" maxlength="2000" rows="2" style="width:100%;padding:8px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--text)">${E(x.review_note || '')}</textarea>
        <div class="row" style="margin-top:8px"><select data-rate="${E(x.id)}"><option value="">Rating</option>${[1, 2, 3, 4, 5].map(n => `<option value="${n}" ${x.rating === n ? 'selected' : ''}>${'★'.repeat(n)}</option>`).join('')}</select>
          <button class="btn tiny" data-rev="${E(x.id)}" data-st="reviewed">Mark reviewed</button><button class="btn tiny ghost" data-rev="${E(x.id)}" data-st="flagged">Flag</button></div></div>`).join('') || '<div class="mini-muted">No submissions.</div>'}</div>`;
    el.querySelector('#admBack').onclick = () => { adm.sel = null; window.viewAdmin(el); };
    el.querySelector('#admApprove').onclick = async () => {
      try { await admRest('profiles?id=eq.' + encodeURIComponent(id), {method: 'PATCH', body: {approved: !row.approved}, headers: {Prefer: 'return=minimal'}}); row.approved = !row.approved; admStudent(el, id); }
      catch (e) { toast(e.offline ? 'No internet connection.' : trunc(e.message, 100)); }
    };
    const roleBtn = el.querySelector('#admRoleBtn');
    if (roleBtn) roleBtn.onclick = async () => {
      const nextRole = row.role === 'teacher' ? 'student' : 'teacher';
      const action = nextRole === 'teacher' ? 'promote this approved student to teacher' : 'return this teacher to student';
      if (!confirm('Are you sure you want to ' + action + '?')) return;
      try {
        await admRpc('admin_set_user_role', {p_user_id: id, p_role: nextRole});
        row.role = nextRole;
        if (nextRole === 'teacher') row.approved = true;
        admStudent(el, id);
      } catch (e) { toast(e.offline ? 'No internet connection.' : trunc(e.message, 120)); }
    };
    el.querySelectorAll('[data-rev]').forEach(b => b.onclick = async () => {
      const sid = b.dataset.rev, note = el.querySelector('#rn-' + sid).value.slice(0, 2000), r = el.querySelector('[data-rate="' + sid + '"]').value;
      try {
        await admRest('submissions?id=eq.' + encodeURIComponent(sid), {method: 'PATCH', headers: {Prefer: 'return=minimal'}, body: {review_status: b.dataset.st, review_note: note || null, rating: r ? +r : null, reviewed_at: new Date().toISOString(), reviewed_by: auth.user.id, student_seen: false}});
        toast('Saved'); admStudent(el, id);
      } catch (e) { toast(e.offline ? 'No internet connection.' : trunc(e.message, 100)); }
    });
  }

  /* ---------------- boot ---------------- */
  function syncNav() {
    if (typeof NAV === 'undefined') return;
    const i = NAV.findIndex(n => n[0] === 'admin');
    if (isAdmin() && i < 0) NAV.splice(1, 0, ['admin', 'nav_admin']);
    if (!isAdmin() && i >= 0) NAV.splice(i, 1);
    try { UI.en.nav_admin = '🛡️ Admin'; } catch (e) {}
    if (typeof buildNav === 'function') buildNav();
  }
  function tick() { touchClock(); renderLock(); renderChip(); if (isStudent() && auth.profile.approved && online() && (sync.dirty || lockState().warn) && Date.now() - (sync.lastAttempt || 0) > 10 * 60000) syncNow(false).catch(() => {}); }
  function startServices() {
    css(); syncNav(); renderChip(); touchClock(); renderLock();
    if (!STORE.__spWrapped) { const orig = STORE.save.bind(STORE); STORE.save = function () { orig(); markDirty(); }; STORE.__spWrapped = true; }
    clearInterval(timer); timer = setInterval(tick, 60000);
    if (!window.__spListeners) { window.__spListeners = true; window.addEventListener('online', tick); document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); }); }
    if (online() && auth && auth.refresh_token) loadProfile().then(() => {
      syncNav(); renderChip(); renderLock();
      // A previously authenticated browser should not silently reset the weekly
      // lock just by opening the page. Explicit OTP sign-in already performs an
      // initial sync in finishLogin(); old sessions sync on activity, retry, or
      // the lock-screen button, so a failed/offline sync never unlocks them.
    }).catch(e => { if (e.status === 400 || e.status === 404) signOut(); });
  }
  function stopServices() { clearInterval(timer); clearTimeout(syncTimer); const c = document.getElementById('spChip'); if (c) c.textContent = ''; const a = document.getElementById('spAcct'); if (a) a.remove(); if (c) c.remove(); }

  function pendingEmailLink() {
    const p = new URLSearchParams(String(location.hash || '').replace(/^#/, ''));
    const type = p.get('type') || '';
    if (!['magiclink', 'email', 'signup'].includes(type)) return null;
    const access_token = p.get('access_token'), refresh_token = p.get('refresh_token');
    if (!access_token || !refresh_token) return null;
    return {access_token, refresh_token, expires_in: Number(p.get('expires_in')) || 3600};
  }
  async function consumeEmailLink(link) {
    try {
      // Get the authoritative user from Auth before creating a local session.
      const r = await http('/auth/v1/user', {token: link.access_token});
      try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
      auth = null;
      setSession({access_token: link.access_token, refresh_token: link.refresh_token,
        expires_in: link.expires_in, user: r.data});
      await loadProfile();
      sync = {uid: auth.user.id};
      touchClock(true); ls.set(K_SYNC, sync);
      await finishLogin(auth.profile);
    } catch (e) {
      auth = null; ls.del(K_AUTH);
      showLogin(e.offline ? 'No internet connection. Open the email link again when online.' :
        'That email link expired or was already used. Request a new email and open the newest link.');
    }
  }

  window.SP_AUTH = Object.assign(window.SP_AUTH, {syncNow, syncLearningState, syncLearningAnswerEvents, recordLearningAnswer, pendingLearningAnswerCount, mergeLearningStates, lockState, signOut, buildSnapshot, isAdmin, isTeacher, isStudent, _state: () => ({auth, sync})});
  css();
  const emailLink = pendingEmailLink();
  if (emailLink) {
    showLogin('Verifying your email sign-in link…');
    consumeEmailLink(emailLink);
  } else if (!auth || !auth.refresh_token) { showLogin(); }
  else { adoptUser(auth.user.id); startServices(); }
})();
