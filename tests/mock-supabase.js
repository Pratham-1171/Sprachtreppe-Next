// In-memory stand-in for the Supabase endpoints the app uses. It mirrors the RLS rules proven in sql.test.js.
function createServer(opts) {
  opts = opts || {};
  const S = {users: new Map(), tokens: new Map(), refresh: new Map(), subs: [], nextSub: 1, assignments: [], assignmentProgress: new Map(), learningStates: new Map(), learningStateRevisions: new Map(), nextAssignment: 1, offline: false, autoConfirm: opts.autoConfirm !== false, log: [], idc: 1};
  const uid = () => 'u' + (S.idc++).toString().padStart(4, '0') + '-0000-0000-0000-000000000000';
  S.addUser = (email, password, o) => { o = o || {}; const key = String(email).trim().toLowerCase(); const u = {id: uid(), email: key, password, full_name: o.name || '', role: o.role || 'student', approved: !!o.approved}; S.users.set(key, u); return u; };
  S.addAssignment = options => {
    options = options || {};
    const id = Number(options.id) || S.nextAssignment++;
    S.nextAssignment = Math.max(S.nextAssignment, id + 1);
    const row = Object.assign({
      id, class_id: null, title: 'German grammar practice', instructions: 'Complete the questions.',
      kind: 'practice', skill: 'grammar', target_count: 5, due_at: null, created_by: null,
      archived: false, created_at: new Date().toISOString()
    }, options, {id});
    S.assignments.push(row);
    return row;
  };
  const byId = id => [...S.users.values()].find(u => u.id === id);
  const session = u => {
    const a = 'at.' + Math.random().toString(36).slice(2), r = 'rt.' + Math.random().toString(36).slice(2);
    S.tokens.set(a, u.id); S.refresh.set(r, u.id);
    return {access_token: a, refresh_token: r, expires_in: 3600, token_type: 'bearer', user: {id: u.id, email: u.email}};
  };
  const caller = h => { const t = (h.Authorization || '').replace('Bearer ', ''); const id = S.tokens.get(t); return id ? byId(id) : null; };
  const isAdmin = u => u && u.role === 'admin' && u.approved;
  const mergeLearningValue = (remote, local, path = []) => {
    if (remote == null) return local == null ? remote : JSON.parse(JSON.stringify(local));
    if (local == null) return JSON.parse(JSON.stringify(remote));
    if (Array.isArray(remote) && Array.isArray(local)) {
      const stable = value => Array.isArray(value) ? '[' + value.map(stable).join(',') + ']' :
        value && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + stable(value[key])).join(',') + '}' : JSON.stringify(value);
      const result = [], seen = new Set();
      for (const item of remote.concat(local)) {
        const key = item && typeof item === 'object' && item.id != null ? 'id:' + item.id : stable(item);
        if (!seen.has(key)) { seen.add(key); result.push(item); }
      }
      return result;
    }
    if (remote && local && typeof remote === 'object' && typeof local === 'object') {
      const result = {};
      for (const key of new Set(Object.keys(remote).concat(Object.keys(local)))) {
        result[key] = !(key in local) ? remote[key] : !(key in remote) ? local[key] :
          mergeLearningValue(remote[key], local[key], path.concat(key));
      }
      return result;
    }
    if (typeof remote === 'number' && typeof local === 'number') return Math.max(remote, local);
    if (typeof remote === 'boolean' && typeof local === 'boolean') return remote || local;
    if (path[path.length - 1] === 'status' && typeof remote === 'string' && typeof local === 'string') {
      const rank = value => ({UNKNOWN:0, NEW:1, WEAK:2, LEARNING:3, FAMILIAR:4, LEARNED:5, STRONG:5, MASTERED:6}[value.toUpperCase()] || 0);
      return rank(local) >= rank(remote) ? local : remote;
    }
    return local;
  };
  const R = (status, body) => ({status, body});
  S.handle = (method, url, headers, body) => {
    const u = new URL(url), p = u.pathname, q = u.searchParams, me = caller(headers);
    S.log.push(method + ' ' + p);
    if (p === '/auth/v1/token' && q.get('grant_type') === 'password') {
      const usr = S.users.get(String(body.email).toLowerCase()) || S.users.get(body.email);
      if (usr && usr.password === body.password && usr.unconfirmed) return R(400, {error_code: 'email_not_confirmed', msg: 'Email not confirmed'});
      return usr && usr.password === body.password ? R(200, session(usr)) : R(400, {error_description: 'Invalid login credentials', error_code: 'invalid_credentials'});
    }
    if (p === '/auth/v1/token' && q.get('grant_type') === 'refresh_token') { const id = S.refresh.get(body.refresh_token); return id ? R(200, session(byId(id))) : R(400, {error_description: 'Invalid Refresh Token'}); }
    if (p === '/auth/v1/signup') {
      if (S.users.has(body.email)) return R(422, {msg: 'User already registered'});
      const usr = S.addUser(body.email, body.password, {name: body.data && body.data.full_name});     // role/approved can never come from the request
      return S.autoConfirm ? R(200, session(usr)) : R(200, {id: usr.id, email: usr.email});
    }
    if (p === '/auth/v1/otp') {
      const email = String(body.email || '').trim().toLowerCase();
      let usr = S.users.get(email);
      if (!usr && body.create_user === true) usr = S.addUser(email, '', {name: body.data && body.data.full_name || '', role: 'student', approved: false});
      if (!usr) return R(422, {error_code: 'otp_disabled', msg: 'Signups not allowed for otp'});
      S.otps = S.otps || {}; S.otps[email] = '482913'; S.otpSent = (S.otpSent || 0) + 1; return R(200, {});
    }
    if (p === '/auth/v1/verify') {
      const email = String(body.email || '').trim().toLowerCase();
      const usr = S.users.get(email);
      if (body.type !== 'email' || !usr || !S.otps || S.otps[email] !== body.token) return R(403, {error_code: 'otp_expired', msg: 'Token has expired or is invalid'});
      delete S.otps[email]; return R(200, session(usr));
    }
    if (p === '/auth/v1/logout') { S.tokens.delete((headers.Authorization || '').replace('Bearer ', '')); return R(204, null); }
    if (p === '/auth/v1/recover') return R(200, {});
    if (p === '/auth/v1/user' && method === 'PUT') { if (!me) return R(401, {msg: 'unauthorized'}); me.password = body.password; return R(200, {id: me.id}); }
    if (!me) return R(401, {message: 'JWT expired or missing', code: 'PGRST301'});
    if (p === '/rest/v1/profiles' && method === 'GET') {
      const id = (q.get('id') || '').replace('eq.', ''); let rows = [...S.users.values()];
      if (!isAdmin(me)) rows = rows.filter(r => r.id === me.id);
      if (id) rows = rows.filter(r => r.id === id);
      return R(200, rows.map(r => ({id: r.id, email: r.email, full_name: r.full_name, role: r.role, approved: r.approved})));
    }
    if (p === '/rest/v1/profiles' && method === 'PATCH') {
      if (!isAdmin(me)) return R(200, []);                                                       // RLS: zero rows
      if (Object.keys(body).some(k => k !== 'approved')) return R(403, {message: 'permission denied', code: '42501'});
      const id = q.get('id').replace('eq.', ''); const t = byId(id); if (t) t.approved = !!body.approved; return R(204, null);
    }
    if (p === '/rest/v1/rpc/complete_student_signup') {
      if (!me || me.role !== 'student' || me.approved) return R(403, {message: 'student registration unavailable', code: '42501'});
      const full = String(body.p_full_name || '').trim().slice(0, 80);
      if (!full) return R(400, {message: 'full name is required', code: '22023'});
      me.full_name = full; return R(200, {id: me.id, email: me.email, full_name: me.full_name, role: me.role, approved: me.approved});
    }
    if (p === '/rest/v1/rpc/admin_set_user_role') {
      if (!isAdmin(me)) return R(403, {message: 'forbidden', code: '42501'});
      if (!['student', 'teacher', 'admin'].includes(body.p_role)) return R(400, {message: 'invalid role', code: '22023'});
      const target = byId(body.p_user_id); if (!target) return R(404, {message: 'user profile not found'});
      target.role = body.p_role; if (body.p_role === 'teacher' || body.p_role === 'admin') target.approved = true;
      return R(200, {id: target.id, email: target.email, full_name: target.full_name, role: target.role, approved: target.approved});
    }
    if (p === '/rest/v1/rpc/sync_learning_state') {
      if (!me.approved || me.role !== 'student') return R(403, {message: 'approved student account required', code: '42501'});
      if (!body.p_state || typeof body.p_state !== 'object' || Array.isArray(body.p_state)) return R(400, {message: 'learning state must be an object'});
      const state = mergeLearningValue(S.learningStates.get(me.id) || {}, body.p_state);
      S.learningStates.set(me.id, state);
      const revision = (S.learningStateRevisions.get(me.id) || 0) + 1;
      S.learningStateRevisions.set(me.id, revision);
      return R(200, {state, revision, updated_at: new Date().toISOString()});
    }
    if (p === '/rest/v1/rpc/submit_progress') {
      if (!me.approved) return R(403, {message: 'account not approved', code: '42501'});
      if (me.role === 'admin') return R(200, {ok: true, skipped: 'admin', feedback: []});
      if (!body.p_payload || typeof body.p_payload.summary !== 'object') return R(400, {message: 'bad payload', code: '22023'});
      const dup = S.subs.find(s => s.student_id === me.id && s.client_id === body.p_client_id);
      if (!dup) S.subs.push({id: S.nextSub++, student_id: me.id, client_id: body.p_client_id, created_at: new Date(S.now ? S.now() : Date.now()).toISOString(), summary: body.p_payload.summary, payload: Object.assign({}, body.p_payload, {summary: undefined}), review_status: 'pending', review_note: null, rating: null, student_seen: true});
      const fb = S.subs.filter(s => s.student_id === me.id && !s.student_seen).map(s => ({id: s.id, status: s.review_status, note: s.review_note, rating: s.rating}));
      return R(200, {ok: true, server_time: new Date(S.now ? S.now() : Date.now()).toISOString(), duplicate: !!dup, feedback: fb});
    }
    if (p === '/rest/v1/rpc/ack_feedback') { S.subs.forEach(s => { if (s.student_id === me.id && body.p_ids.includes(s.id)) s.student_seen = true; }); return R(204, null); }
    if (p === '/rest/v1/rpc/my_classroom') {
      if (!me.approved) return R(403, {message: 'account not approved', code: '42501'});
      const rows = S.assignments.filter(a => !a.archived && (a.class_id == null || isAdmin(me) || me.role === 'teacher')).map(a => {
        const progress = S.assignmentProgress.get(me.id + ':' + a.id) || {done: 0, correct: 0};
        return Object.assign({}, a, {done: progress.done, correct: progress.correct, completed_count: progress.done});
      });
      return R(200, {classes: [], assignments: rows, announcements: []});
    }
    if (p === '/rest/v1/rpc/update_assignment_progress') {
      if (!me.approved || me.role !== 'student') return R(403, {message: 'forbidden', code: '42501'});
      const id = Number(body.p_assignment), assignment = S.assignments.find(a => a.id === id && !a.archived);
      if (!Number.isSafeInteger(id) || !assignment) return R(404, {message: 'assignment not found', code: 'P0002'});
      if (assignment.class_id != null) return R(403, {message: 'not a class member', code: '42501'});
      const done = Number(body.p_done), correct = Number(body.p_correct);
      if (!Number.isInteger(done) || !Number.isInteger(correct) || done < 0 || done > assignment.target_count || correct < 0 || correct > done) {
        return R(400, {message: 'invalid progress values', code: '22023'});
      }
      const key = me.id + ':' + id;
      const old = S.assignmentProgress.get(key) || {done: 0, correct: 0};
      const mergedDone = Math.max(old.done, done);
      const mergedCorrect = Math.min(mergedDone, Math.max(old.correct, correct));
      S.assignmentProgress.set(key, {assignment_id: id, student_id: me.id, done: mergedDone, correct: mergedCorrect});
      return R(200, null);
    }
    if (p === '/rest/v1/rpc/admin_overview') {
      if (!isAdmin(me)) return R(403, {message: 'forbidden', code: '42501'});
      return R(200, [...S.users.values()].map(r => { const ss = S.subs.filter(s => s.student_id === r.id).sort((a, b) => b.id - a.id); return {id: r.id, email: r.email, full_name: r.full_name, role: r.role, approved: r.approved, created_at: new Date().toISOString(), last_sync_at: ss[0] ? ss[0].created_at : null, submissions: ss.length, unreviewed: ss.filter(s => s.review_status === 'pending').length, last_summary: ss[0] ? ss[0].summary : null}; }));
    }
    if (p === '/rest/v1/submissions' && method === 'GET') {
      let rows = S.subs.slice(); const sid = q.get('student_id'), id = q.get('id');
      if (!isAdmin(me)) rows = rows.filter(s => s.student_id === me.id);
      if (sid) rows = rows.filter(s => s.student_id === sid.replace('eq.', ''));
      if (id) rows = rows.filter(s => String(s.id) === id.replace('eq.', ''));
      return R(200, rows.sort((a, b) => b.id - a.id).map(s => JSON.parse(JSON.stringify(s))));
    }
    if (p === '/rest/v1/submissions' && method === 'PATCH') {
      if (!isAdmin(me)) return R(200, []);
      const id = +q.get('id').replace('eq.', ''), s = S.subs.find(x => x.id === id);
      if (s) Object.assign(s, body); return R(204, null);
    }
    return R(404, {message: 'not found ' + p});
  };
  S.fetch = async (url, init) => {
    init = init || {};
    if (S.offline) throw new TypeError('Failed to fetch');
    const r = S.handle(init.method || 'GET', url, init.headers || {}, init.body ? JSON.parse(init.body) : undefined);
    const text = r.body == null ? '' : JSON.stringify(r.body);
    return {ok: r.status >= 200 && r.status < 300, status: r.status, text: async () => text, headers: {get: () => new Date().toUTCString()}};
  };
  return S;
}
module.exports = {createServer};
