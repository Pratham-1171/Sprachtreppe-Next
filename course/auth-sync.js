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
  async function signIn(email, password) {
    const r = await http('/auth/v1/token?grant_type=password', {method: 'POST', body: {email: String(email).trim(), password}});
    auth = null; setSession(r.data);
    await loadProfile();
    if (!sync.uid || sync.uid !== auth.user.id) { sync = {uid: auth.user.id}; }
    touchClock(true); ls.set(K_SYNC, sync);
    return auth.profile;
  }
  async function signUp(email, password, name) {
    const r = await http('/auth/v1/signup', {method: 'POST', body: {email: String(email).trim(), password, data: {full_name: String(name || '').slice(0, 80)}}});
    return r.data;
  }
  async function signOut() {
    try { if (auth && auth.access_token && online()) await http('/auth/v1/logout', {method: 'POST', token: auth.access_token, timeout: 5000}); } catch (e) {}
    auth = null; ls.del(K_AUTH); stopServices(); showLogin();
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
    return {summary, mistakes, writing, sessions, activity};
  }
  const newId = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : (Date.now().toString(36) + Math.random().toString(36).slice(2, 12));

  /* ---------------- sync ---------------- */
  async function syncNow(manual) {
    if (inflight) return inflight;
    inflight = (async () => {
      sync.lastAttempt = Date.now(); ls.set(K_SYNC, sync);
      if (!isStudent()) return {skipped: 'admin'};
      try {
        if (!auth.profile.approved) { await loadProfile(); if (!auth.profile.approved) { renderChip(); return {pending: true}; } }
        const t = await token();
        const r = await http('/rest/v1/rpc/submit_progress', {method: 'POST', token: t, body: {p_payload: buildSnapshot(), p_client_id: newId()}});
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

  /* ---------------- admin sign-in with an emailed one-time code ---------------- */
  async function sendCode(email) {
    // Keep Supabase's non-enumerating behavior for unknown email addresses.
    // Surface rate limits, connectivity errors, and server/provider failures.
    try {
      await http('/auth/v1/otp?redirect_to=' + encodeURIComponent('https://pratham-1171.github.io/German_A1-B1/'), {method: 'POST', body: {email: String(email).trim(), create_user: false}});
    } catch (e) {
      if (e.offline || e.status === 429 || e.status >= 500) throw e;
      // For other client errors, keep the same UI response to avoid exposing
      // whether an email address is registered.
    }
  }
  async function verifyCode(email, code) {
    const r = await http('/auth/v1/verify', {method: 'POST', body: {type: 'email', email: String(email).trim(), token: String(code).replace(/\s+/g, '')}});
    auth = null; setSession(r.data); await loadProfile();
    if (!sync.uid || sync.uid !== auth.user.id) sync = {uid: auth.user.id};
    touchClock(true); ls.set(K_SYNC, sync);
    return auth.profile;
  }

  /* ---------------- login screen ---------------- */
  function showLogin(msg) {
    css(); document.body.classList.add('sp-locked');
    let box = document.getElementById('spAuth'); if (box) box.remove();
    const lock = document.getElementById('spLock'); if (lock) lock.remove();
    box = document.createElement('div'); box.id = 'spAuth';
    let mode = 'in', who = 'student', method = 'password', codeSent = false, resendAt = 0;
    const draw = () => {
      const adminCode = who === 'admin' && method === 'code';
      box.innerHTML = `<form class="sp-card" id="spForm" autocomplete="on" novalidate>
        <h2>🇩🇪 Sprachtreppe</h2><div class="mini-muted">${who === 'admin' ? 'Teacher / admin sign-in' : 'Student sign-in'}</div>
        <div class="sp-tabs"><button type="button" class="btn small ${who === 'student' ? '' : 'ghost'}" data-who="student">Student</button><button type="button" class="btn small ${who === 'admin' ? '' : 'ghost'}" data-who="admin">Admin</button></div>
        ${mode === 'up' && who === 'student' ? '<label for="spName">Your name</label><input id="spName" autocomplete="name" maxlength="80">' : ''}
        <label for="spEmail">Email</label><input id="spEmail" type="email" inputmode="email" autocomplete="username" required>
        ${adminCode ? (codeSent ? '<label for="spCode">Code from the email</label><input id="spCode" inputmode="numeric" autocomplete="one-time-code" maxlength="10">' : '')
          : `<label for="spPw">Password</label><input id="spPw" type="password" autocomplete="${mode === 'up' ? 'new-password' : 'current-password'}" minlength="10" required>`}
        <div class="sp-err" id="spErr" role="alert">${E(msg || '')}</div>
        <button class="btn" style="width:100%;margin-top:6px" type="submit">${adminCode ? (codeSent ? 'Verify and sign in' : 'Send me a code') : mode === 'up' ? 'Create student account' : 'Sign in'}</button>
        <div style="display:flex;justify-content:space-between;margin-top:12px;font-size:13px;gap:10px">
          ${who === 'student' ? `<a href="#" id="spSwitch">${mode === 'up' ? 'I already have an account' : 'Create account'}</a>` : `<a href="#" id="spMethod">${adminCode ? 'Use password instead' : 'Use an emailed code instead'}</a>`}
          ${adminCode ? (codeSent ? '<a href="#" id="spResend">Send a new code</a>' : '<span></span>') : '<a href="#" id="spForgot">Forgot password?</a>'}</div>
        <div class="mini-muted" style="margin-top:12px">Internet is needed to sign in and once a week to send your progress to your teacher.</div></form>`;
      box.querySelectorAll('[data-who]').forEach(b => b.onclick = () => { who = b.dataset.who; method = who === 'admin' ? 'code' : 'password'; codeSent = false; if (who === 'admin') mode = 'in'; msg = ''; draw(); });
      const sw = box.querySelector('#spSwitch'); if (sw) sw.onclick = e => { e.preventDefault(); mode = mode === 'up' ? 'in' : 'up'; msg = ''; draw(); };
      const mt = box.querySelector('#spMethod'); if (mt) mt.onclick = e => { e.preventDefault(); method = method === 'code' ? 'password' : 'code'; codeSent = false; msg = ''; draw(); };
      const rs = box.querySelector('#spResend');
      if (rs) rs.onclick = e => {
        e.preventDefault();
        const waitMs = resendAt - Date.now();
        if (waitMs > 0) { setErr('Wait ' + Math.ceil(waitMs / 1000) + ' seconds before requesting another code.'); return; }
        codeSent = false; msg = ''; draw();
      };
      const fg = box.querySelector('#spForgot');
      if (fg) fg.onclick = async e => {
        e.preventDefault(); const em = box.querySelector('#spEmail').value.trim();
        if (!em) { setErr('Enter your email first.'); return; }
        const resetRedirect = 'https://pratham-1171.github.io/German_A1-B1/';
        try {
          await http('/auth/v1/recover?redirect_to=' + encodeURIComponent(resetRedirect), {method: 'POST', body: {email: em}});
          setErr('If the address is registered, a reset email has been sent. Open the newest email in your browser. The link expires and can only be used once.', true);
        } catch (er) {
          setErr(er.offline ? 'No internet connection.' : er.status === 429
            ? 'Too many reset requests. Wait a minute before trying again.'
            : 'Could not send the email. Check Supabase Auth email settings and try again.');
        }
      };
      box.querySelector('#spForm').onsubmit = submit;
    };
    const setErr = (m, ok) => { const el = box.querySelector('#spErr'); el.textContent = m; el.className = 'sp-err' + (ok ? ' sp-ok' : ''); };
    const submit = async ev => {
      ev.preventDefault();
      const email = box.querySelector('#spEmail').value;
      if (Date.now() < cooldownUntil) { setErr('Too many attempts. Wait ' + Math.ceil((cooldownUntil - Date.now()) / 1000) + ' s.'); return; }
      if (!/^\S+@\S+\.\S+$/.test(email)) { setErr('Enter a valid email address.'); return; }
      const btn = box.querySelector('button[type=submit]');
      const notAdmin = () => { const tk = auth && auth.access_token; auth = null; ls.del(K_AUTH); if (tk) http('/auth/v1/logout', {method: 'POST', token: tk, timeout: 5000}).catch(() => {}); setErr('This account is not an administrator.'); btn.disabled = false; };
      if (who === 'admin' && method === 'code') {
        btn.disabled = true;
        if (!codeSent) {
          try {
            await sendCode(email);
            const keep = email;
            codeSent = true; resendAt = Date.now() + 30000; msg = ''; draw();
            box.querySelector('#spEmail').value = keep;
            setErr('If this address belongs to an administrator, a code was sent. Check inbox and spam. For a numeric code, Supabase → Authentication → Email Templates → Magic Link must contain {{ .Token }}.', true);
          } catch (e) {
            setErr(e.offline ? 'No internet connection.'
              : e.status === 429 ? 'Supabase is limiting email requests. Wait at least 30–60 seconds before retrying.'
              : 'Could not send the login email. Check Supabase Auth email settings and try again.');
            btn.disabled = false;
          }
          return;
        }
        const code = box.querySelector('#spCode').value.replace(/\s+/g, '');
        if (!/^\d{6,10}$/.test(code)) { setErr('Enter the code from the email (digits only).'); btn.disabled = false; return; }
        try {
          const prof = await verifyCode(email, code); failedLogins = 0;
          if (prof.role !== 'admin') { notAdmin(); return; }
          await finishLogin(prof, who);
        } catch (e) {
          if (!e.offline) { failedLogins++; if (failedLogins >= 5) { cooldownUntil = Date.now() + 30000; failedLogins = 0; } }
          setErr(e.offline ? 'No internet connection. Sign-in needs internet.' : e.status === 429 ? 'Too many attempts — try again later.' : 'Invalid or expired code.');
          btn.disabled = false;
        }
        return;
      }
      const pw = box.querySelector('#spPw').value;
      if (mode === 'up' && (pw.length < 10 || !/[a-zA-Z]/.test(pw) || !/\d/.test(pw))) { setErr('Use at least 10 characters with letters and digits.'); return; }
      if (!pw) { setErr('Enter your password.'); return; }
      btn.disabled = true;
      try {
        if (mode === 'up') {
          const nm = (box.querySelector('#spName') || {}).value || '';
          const data = await signUp(email, pw, nm);
          box.querySelector('#spPw').value = '';
          if (data && data.access_token) { await finishLogin(await signIn(email, pw), who); return; }
          mode = 'in'; draw(); setErr('Account created. Confirm your email if you received a message, then sign in. Your teacher must approve you before your progress is counted.', true); return;
        }
        const prof = await signIn(email, pw);
        box.querySelector('#spPw').value = ''; failedLogins = 0;
        if (who === 'admin' && prof.role !== 'admin') { notAdmin(); return; }
        await finishLogin(prof, who);
      } catch (e) {
        if (!e.offline) { failedLogins++; if (failedLogins >= 5) { cooldownUntil = Date.now() + 30000; failedLogins = 0; } }
        setErr(e.offline ? 'No internet connection. Sign-in needs internet.' : (e.code === 'email_not_confirmed' || /email not confirmed/i.test(e.message || '')) ? 'Your email address is not confirmed yet. Open the confirmation email, or ask your teacher to confirm your account.' : e.status === 429 ? 'Too many attempts — try again later.' : mode === 'up' ? trunc(e.message, 140) : 'Invalid email or password.');
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
    const fb = (sync.feedback || []).slice(0, 8);
    el.innerHTML = `<h2>Account</h2>
      <div class="card"><div><b>${E(p.full_name || p.email)}</b></div><div class="mini-muted">${E(p.email)}</div>
        <div style="margin-top:8px"><span class="sp-badge ${isAdmin() ? 'ok' : p.approved ? 'ok' : 'warn'}">${isAdmin() ? 'Administrator' : p.approved ? 'Student · approved' : 'Student · waiting for approval'}</span></div>
        ${isStudent() ? `<p class="mini-muted" style="margin-top:12px;line-height:1.6">Last sent to your teacher: <b>${sync.lastOk ? fmtAgo(new Date(sync.lastOk).toISOString()) : 'not yet'}</b><br>Next sync due within: <b>${Math.ceil(st.left)} days</b> (every ${SYNC_DAYS} days)</p>
        <div class="row"><button class="btn" id="spSyncBtn">🔄 Sync now</button></div><div id="spSyncMsg" class="mt mini-muted">${sync.lastError ? E(sync.lastError === 'offline' ? 'Offline — will retry when connected.' : sync.lastError) : ''}</div>` : ''}
      </div>
      ${fb.length ? `<h3>Teacher feedback</h3><div class="card">${fb.map(f => `<div style="margin-bottom:12px"><span class="sp-badge ${f.status === 'flagged' ? 'bad' : 'ok'}">${E(f.status)}</span> ${f.rating ? '★'.repeat(f.rating | 0) : ''}<div style="margin-top:6px;white-space:pre-wrap">${E(f.note || '(no comment)')}</div></div>`).join('')}</div>` : ''}
      <h3>Change password</h3><div class="card sp-card" style="width:auto;box-shadow:none;border:0;padding:0">
        <label for="spNewPw">New password (10+ characters)</label><input id="spNewPw" type="password" autocomplete="new-password">
        <div class="row"><button class="btn ghost" id="spPwBtn">Update password</button></div><div id="spPwMsg" class="mt mini-muted"></div></div>
      <div class="row" style="margin-top:16px"><button class="btn ghost" id="spOutBtn">Sign out</button></div>`;
    const sb = el.querySelector('#spSyncBtn');
    if (sb) sb.onclick = async () => { const m = el.querySelector('#spSyncMsg'); m.textContent = 'Syncing…'; try { const r = await syncNow(true); m.textContent = r && r.pending ? 'Waiting for teacher approval.' : 'Sent ✔'; setTimeout(() => window.viewAccount(el), 700); } catch (e) { m.textContent = e.offline ? 'No internet connection.' : trunc(e.message, 120); } };
    el.querySelector('#spPwBtn').onclick = async () => {
      const m = el.querySelector('#spPwMsg'), pw = el.querySelector('#spNewPw').value;
      if (pw.length < 10 || !/[a-zA-Z]/.test(pw) || !/\d/.test(pw)) { m.textContent = 'Use 10+ characters with letters and digits.'; return; }
      try { await http('/auth/v1/user', {method: 'PUT', token: await token(), body: {password: pw}}); el.querySelector('#spNewPw').value = ''; m.textContent = 'Password updated ✔'; } catch (e) { m.textContent = e.offline ? 'No internet connection.' : trunc(e.message, 120); }
    };
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
      <div style="margin:10px 0">${row.approved ? '<span class="sp-badge ok">approved</span>' : '<span class="sp-badge warn">pending</span>'} ${overdue(row) ? '<span class="sp-badge bad">overdue</span>' : ''}
        <button class="btn tiny" id="admApprove">${row.approved ? 'Disable account' : 'Approve account'}</button></div>
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
    if (online() && auth && auth.refresh_token) loadProfile().then(() => { syncNav(); renderChip(); renderLock(); }).catch(e => { if (e.status === 400 || e.status === 404) signOut(); });
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

  window.SP_AUTH = Object.assign(window.SP_AUTH, {syncNow, lockState, signOut, buildSnapshot, isAdmin, isTeacher, isStudent, _state: () => ({auth, sync})});
  css();
  const emailLink = pendingEmailLink();
  if (emailLink) {
    showLogin('Verifying your email sign-in link…');
    consumeEmailLink(emailLink);
  } else if (!auth || !auth.refresh_token) { showLogin(); }
  else { adoptUser(auth.user.id); startServices(); }
})();
