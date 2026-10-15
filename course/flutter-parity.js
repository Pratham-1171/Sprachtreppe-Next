/* Flutter-parity layer for the browser build. Keeps the full web exercise engine and adds Flutter's compact role-based workspace. */
(function () {
  'use strict';
  var role = function () {
    var s = window.SP_AUTH && window.SP_AUTH._state ? window.SP_AUTH._state() : {};
    return (s.auth && s.auth.profile && s.auth.profile.role) || 'student';
  };
  var profile = function () {
    var s = window.SP_AUTH && window.SP_AUTH._state ? window.SP_AUTH._state() : {};
    return (s.auth && s.auth.profile) || {};
  };
  var userId = function () {
    var s = window.SP_AUTH && window.SP_AUTH._state ? window.SP_AUTH._state() : {};
    return (s.auth && s.auth.user && s.auth.user.id) || (s.auth && s.auth.profile && s.auth.profile.id) || 'local';
  };
  var key = function (name) { return 'sp_' + name + '_v1_' + userId(); };
  var getJson = function (k, fallback) {
    try { var v = JSON.parse(localStorage.getItem(k) || 'null'); return v == null ? fallback : v; } catch (_) { return fallback; }
  };
  var setJson = function (k, value) { try { localStorage.setItem(k, JSON.stringify(value)); } catch (_) {} };
  var node = function (tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = String(text);
    return n;
  };
  var button = function (label, fn, cls) {
    var b = node('button', cls || 'btn', label);
    b.type = 'button';
    b.addEventListener('click', fn);
    return b;
  };
  var go = function (route) { location.hash = '#/' + route; };
  var heading = function (host, title, sub, badge) {
    var h = node('div', 'fp-head');
    var left = node('div', '');
    left.appendChild(node('h2', '', title));
    if (sub) left.appendChild(node('p', 'sub', sub));
    h.appendChild(left);
    if (badge) h.appendChild(node('span', 'fp-role', badge));
    host.appendChild(h);
  };
  var card = function (title, body, icon) {
    var c = node('div', 'fp-card');
    var top = node('div', 'fp-card-top');
    if (icon) top.appendChild(node('span', 'fp-icon', icon));
    top.appendChild(node('h3', '', title));
    c.appendChild(top);
    if (body) c.appendChild(node('p', 'fp-muted', body));
    return c;
  };
  var grid = function (host) { var g = node('div', 'fp-grid'); host.appendChild(g); return g; };
  var linkCard = function (host, title, body, route, icon) {
    var c = card(title, body, icon);
    c.tabIndex = 0;
    c.setAttribute('role', 'link');
    c.addEventListener('click', function () { go(route); });
    c.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(route); } });
    host.appendChild(c);
    return c;
  };
  var appendStyles = function () {
    if (document.getElementById('spFlutterParity')) return;
    var s = node('style');
    s.id = 'spFlutterParity';
    s.textContent = [
      '.fp-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:14px;min-width:0}',
      '.fp-head>div{min-width:0}.fp-head h2{margin:0 0 4px}.fp-head .sub{margin:4px 0 0}',
      '.fp-role{flex:0 0 auto;border:1px solid var(--line);border-radius:999px;padding:5px 10px;font-size:11px;font-weight:800;color:var(--accent);white-space:nowrap}',
      '.fp-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,210px),1fr));gap:10px;margin:10px 0 18px;min-width:0}',
      '.fp-card{min-width:0;max-width:100%;border:1px solid var(--line);border-radius:14px;background:var(--card);padding:15px;box-shadow:var(--shadow);overflow-wrap:anywhere}',
      '.fp-card[role=link]{cursor:pointer;transition:border-color .15s,transform .15s}.fp-card[role=link]:hover,.fp-card[role=link]:focus-visible{border-color:var(--accent2);outline:none;transform:translateY(-1px)}',
      '.fp-card h3{margin:0 0 7px;font-size:16px}.fp-card-top{display:flex;align-items:center;gap:9px;margin-bottom:7px}.fp-card-top h3{margin:0}',
      '.fp-icon{font-size:22px}.fp-muted{color:var(--muted);font-size:12.5px;line-height:1.55;margin:0;overflow-wrap:anywhere}',
      '.fp-actions{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.fp-actions .btn{flex:0 1 auto;min-width:0;white-space:normal}',
      '.fp-filter{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0 14px}.fp-filter button{border:1px solid var(--line);border-radius:999px;background:var(--card);color:var(--text);padding:8px 13px;min-height:40px;font:inherit;cursor:pointer}.fp-filter button.active{background:color-mix(in oklch,var(--accent2) 22%,var(--card));border-color:var(--accent2)}',
      '.fp-topic-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,220px),1fr));gap:7px;margin-top:10px}.fp-topic{padding:8px 10px;border-radius:9px;background:var(--bg);border:1px solid var(--line);font-size:12.5px;overflow-wrap:anywhere}',
      '.fp-progress{height:8px;border-radius:99px;overflow:hidden;background:var(--line);margin:9px 0}.fp-progress i{display:block;height:100%;background:linear-gradient(90deg,var(--accent),var(--accent2))}',
      '.fp-note{border-left:4px solid var(--accent2);background:var(--bg);padding:11px 13px;border-radius:9px;margin:10px 0;font-size:12.5px;line-height:1.6;overflow-wrap:anywhere}',
      '.fp-overview{margin:16px 0;border:1px solid var(--line);border-radius:14px;padding:14px;background:var(--card)}.fp-overview h3{margin:0 0 8px}',
      '.fp-mini-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,120px),1fr));gap:8px;margin:10px 0}.fp-mini{padding:10px;border:1px solid var(--line);border-radius:10px;background:var(--bg);min-width:0}.fp-mini b{display:block;font-size:20px;color:var(--accent);overflow-wrap:anywhere}.fp-mini span{font-size:11.5px;color:var(--muted)}',
      '.fp-search{width:100%;max-width:100%;min-width:0;margin:5px 0 10px}.fp-empty{padding:22px 12px;text-align:center;color:var(--muted);border:1px dashed var(--line);border-radius:12px;line-height:1.6}',
      '.fp-task-card{display:block;margin-bottom:10px}.fp-task-card .fp-task-meta{display:flex;gap:7px;flex-wrap:wrap;font-size:11.5px;color:var(--muted)}.fp-pill{display:inline-flex;border:1px solid var(--line);border-radius:999px;padding:3px 8px;font-size:11px;max-width:100%;overflow-wrap:anywhere}',
      '.fp-task-card p{white-space:pre-wrap;overflow-wrap:anywhere}.fp-task-card textarea{width:100%;min-height:150px;resize:vertical;margin:8px 0}.fp-task-card input{width:100%;min-width:0}',
      '.fp-notify{position:relative!important}.fp-notify-count{position:absolute;top:-3px;right:-3px;min-width:17px;height:17px;padding:0 4px;display:grid;place-items:center;border-radius:99px;background:var(--warn);color:#fff;font-size:9px;font-weight:800;border:2px solid var(--card)}',
      '.fp-practice-bar{border:1px solid var(--line);border-radius:12px;background:var(--card);padding:12px;margin:0 0 14px}.fp-practice-bar h2{margin:0 0 4px;font-size:20px}.fp-practice-bar .fp-actions{margin-bottom:0}',
      'html,body{max-width:100%;overflow-x:hidden}.fp-grid>*{min-width:0}@media(max-width:650px){.fp-head{gap:8px}.fp-card{padding:12px}.fp-actions .btn{flex:1 1 140px}.fp-role{max-width:38vw;white-space:normal;text-align:center}.fp-topic-list{grid-template-columns:minmax(0,1fr)}}'
    ].join('');
    document.head.appendChild(s);
  };

  var courseModules = [
    {level:'A1',title:'Build the foundations',desc:'Everyday German sentences and the first cases.',topics:['sein and haben','Personal pronouns and verb endings','Articles and nominative','Accusative','First dative patterns','Modal verbs','Separable verbs','nicht vs. kein','Questions and word order','Imperative','Perfekt']},
    {level:'A2',title:'Join ideas and describe experiences',desc:'Connect ideas, control cases and use common A2 patterns.',topics:['weil and dass','wenn vs. als','Indirect questions: ob and W-words','deshalb and trotzdem','Modal verbs in Präteritum','Konjunktiv II requests','Adjective endings','Reflexive verbs','Comparison','Two-way prepositions','Verb-preposition pairs','Infinitive clauses with zu']},
    {level:'B1',title:'Explain, compare and argue clearly',desc:'Build longer explanations and express relationships precisely.',topics:['Plusquamperfekt','Past Konjunktiv II','Passive with modal verbs','Indirect speech','Genitive','N-declension','Relative clauses with prepositions','Two-part connectors','Purpose clauses','Futur I assumptions','Participles as adjectives','Process vs. resulting state']}
  ];
  var selectedCourseLevel = 'A1';
  function viewFlutterCourse(host) {
    appendStyles();
    host.replaceChildren();
    heading(host, 'Course', 'Follow the A1 → B1 progression with focused grammar and practical topics.', 'LEARNING');
    var filters = node('div', 'fp-filter');
    ['A1','A2','B1'].forEach(function (level) {
      var b = button(level, function () { selectedCourseLevel = level; viewFlutterCourse(host); }, selectedCourseLevel === level ? 'active' : '');
      if (selectedCourseLevel === level) b.classList.add('active');
      filters.appendChild(b);
    });
    host.appendChild(filters);
    var selected = courseModules.filter(function (m) { return m.level === selectedCourseLevel; });
    selected.forEach(function (m) {
      var c = card(m.level + ' · ' + m.title, m.desc, '📘');
      var details = node('details', 'fp-details');
      var summary = node('summary', '', m.topics.length + ' topics · Open syllabus');
      details.appendChild(summary);
      var topics = node('div', 'fp-topic-list');
      m.topics.forEach(function (topic) { topics.appendChild(node('div', 'fp-topic', topic)); });
      details.appendChild(topics);
      c.appendChild(details);
      var actions = node('div', 'fp-actions');
      actions.appendChild(button('Study grammar', function () { go('grammar'); }, 'btn'));
      actions.appendChild(button('Explore words', function () { go('vocab'); }, 'btn ghost'));
      c.appendChild(actions);
      host.appendChild(c);
    });
    var note = node('div', 'fp-note', 'The browser keeps the full existing exercise engine. Choose Grammar or Words to open the interactive lessons and practice screens.');
    host.appendChild(note);
  }

  var learnCards = [
    ['📘','Course','A1, A2 and B1 topic roadmap','course'],
    ['📚','Vocabulary','Words, articles, meanings and spaced review','vocab'],
    ['📖','Grammar','Rules, examples and interactive grammar practice','grammar'],
    ['⚡','Practice','Quizzes, articles and guided question rounds','practice'],
    ['🧠','Smart Review','Review words due for practice','review'],
    ['🗂️','Flashcards','Spaced-repetition flashcards','flash'],
    ['🔥','Verbs','Verb usage and conjugation practice','verbs'],
    ['🔗','Connectors','Link ideas and understand word order','connectors'],
    ['🧱','Collocations','Learn words that naturally go together','collocations'],
    ['🧩','Sentence Builder','Build correct German sentences','sentence'],
    ['✏️','Spelling','Practise spelling and word forms','spelling'],
    ['📝','Dictation','Listen and type what you hear','dictation'],
    ['🎧','Listening','Listening comprehension','listen'],
    ['🗣️','Speaking','Speaking prompts and pronunciation','speak'],
    ['📄','Reading','Reading comprehension','read'],
    ['✍️','Writing','Writing prompts and feedback records','write'],
    ['🎯','Exam Practice','Exam-oriented practice sets','exam'],
    ['❌','Mistakes','Review your recurring mistakes','mistakes'],
    ['📈','Progress','Your activity and learning progress','progress'],
    ['🔊','Pronunciation','Listen to German words and sentences','pronounce'],
    ['📰','Resources','Learning references and extra resources','resources']
  ];
  function viewFlutterLearn(host) {
    appendStyles();
    host.replaceChildren();
    heading(host, 'Learn German', 'Choose a learning area. Your existing exercises, vocabulary and grammar library remain available.', 'A1 → B1');
    var actions = node('div', 'fp-actions');
    actions.appendChild(button('Start a quick practice', function () { go('practice'); }, 'btn'));
    actions.appendChild(button('Open daily session', function () { go('session'); }, 'btn ghost'));
    host.appendChild(actions);
    var g = grid(host);
    learnCards.forEach(function (c) { linkCard(g, c[1], c[2], c[3], c[0]); });
  }

  var originalHome = window.viewHome;
  function viewFlutterHome(host) {
    if (typeof originalHome === 'function' && originalHome !== viewFlutterHome) originalHome(host);
    else { host.replaceChildren(); heading(host, 'Sprachtreppe', 'Continue learning German from A1 to B1.'); }
    appendStyles();
    var p = profile();
    if (!p.id && !userId().match(/^[0-9a-f-]{30,}$/i)) return;
    var panel = node('section', 'fp-overview');
    panel.appendChild(node('h3', '', 'Your learning space'));
    panel.appendChild(node('p', 'fp-muted', 'Quick access to the main areas, notifications and your next progress sync.'));
    var stats = node('div', 'fp-mini-grid');
    var syncState = window.SP_AUTH && window.SP_AUTH.lockState ? window.SP_AUTH.lockState() : {locked:false,warn:false,left:7};
    var syncLabel = syncState.locked ? 'Sync required' : syncState.warn ? 'Sync due soon' : 'Up to date';
    var syncValue = syncState.locked ? 'Now' : (syncState.left == null ? '—' : Math.ceil(syncState.left) + 'd');
    var a = node('div', 'fp-mini'); a.appendChild(node('b', '', syncValue)); a.appendChild(node('span', '', syncLabel)); stats.appendChild(a);
    var n = node('div', 'fp-mini'); n.appendChild(node('b', '', '…')); n.appendChild(node('span', '', 'Unread notifications')); stats.appendChild(n);
    panel.appendChild(stats);
    var actions = node('div', 'fp-actions');
    actions.appendChild(button('Learn', function () { go('learn'); }, 'btn'));
    actions.appendChild(button('Practice', function () { go('practice'); }, 'btn ghost'));
    actions.appendChild(button('Tasks', function () { go('assignments'); }, 'btn ghost'));
    actions.appendChild(button('Notifications', function () { go('notifications'); }, 'btn ghost'));
    if (window.SP_AUTH && window.SP_AUTH.syncNow && (syncState.warn || syncState.locked)) {
      actions.appendChild(button('Sync now', async function (e) {
        var b = e.currentTarget; b.disabled = true; b.textContent = 'Syncing…';
        try { await window.SP_AUTH.syncNow(true); b.textContent = 'Synced'; }
        catch (_) { b.textContent = 'Retry sync'; }
        finally { b.disabled = false; }
      }, 'btn'));
    }
    panel.appendChild(actions);
    var today = host.querySelector('.today-dash');
    if (today && today.parentNode) today.insertAdjacentElement('afterend', panel);
    else host.prepend(panel);
    if (window.SP_LMS && window.SP_LMS.notificationCount) {
      window.SP_LMS.notificationCount().then(function (rows) {
        var unread = Array.isArray(rows) ? rows.filter(function (item) { return !item.read_at; }).length : 0;
        n.firstChild.textContent = String(unread);
      }).catch(function () { n.firstChild.textContent = '—'; });
    } else { n.firstChild.textContent = '—'; }
    if (window.SP_LMS && window.SP_LMS.rpc) {
      window.SP_LMS.rpc('my_classroom').then(function (data) {
        if (!panel.isConnected) return;
        var counts = node('div', 'fp-mini-grid');
        var classes = Array.isArray(data && data.classes) ? data.classes : [];
        var assignments = Array.isArray(data && data.assignments) ? data.assignments : [];
        var announcements = Array.isArray(data && data.announcements) ? data.announcements : [];
        [[classes.length,'Classes'],[assignments.length,'Assignments'],[announcements.length,'News items']].forEach(function (v) {
          var m = node('div', 'fp-mini'); m.appendChild(node('b', '', v[0])); m.appendChild(node('span', '', v[1])); counts.appendChild(m);
        });
        panel.appendChild(counts);
      }).catch(function () {
        if (panel.isConnected) panel.appendChild(node('p', 'fp-muted', 'Class and assignment summaries will appear here when the classroom workspace is available.'));
      });
    }
  }

  function viewFlutterPractice(host) {
    appendStyles();
    if (typeof window.viewQuiz === 'function') window.viewQuiz(host);
    else { host.replaceChildren(); heading(host, 'Practice', 'Choose an exercise to strengthen your German.'); }
    var bar = node('section', 'fp-practice-bar');
    bar.appendChild(node('h2', '', 'Practice'));
    var active = getJson(key('task_active'), null);
    if (active && active.assignment_id) {
      var all = getJson(key('task_progress'), {});
      var prog = all[String(active.assignment_id)] || {};
      var done = prog.done || active.done || 0;
      var target = prog.target_count || active.target_count || 10;
      var activeLabel = node('p', 'fp-muted', 'Assignment: ' + (active.title || 'Practice task') + ' · ' + Math.min(done,target) + ' / ' + target + ' questions'); activeLabel.setAttribute('data-active-task-progress',''); bar.appendChild(activeLabel);
      var track = node('div', 'fp-progress'); var fill = node('i'); fill.style.width = Math.min(100, Math.round(done / Math.max(1,target) * 100)) + '%'; track.appendChild(fill); bar.appendChild(track);
      bar.appendChild(button('Back to tasks', function () { go('assignments'); }, 'btn ghost'));
    } else {
      bar.appendChild(node('p', 'fp-muted', 'Choose the exercise type and difficulty inside the quiz, or continue from an assigned task.'));
    }
    var actions = node('div', 'fp-actions');
    [['Smart review','review'],['Flashcards','flash'],['Vocabulary','vocab'],['Grammar','grammar'],['Mistakes','mistakes'],['Exam practice','exam']].forEach(function (v) {
      actions.appendChild(button(v[0], function () { go(v[1]); }, 'btn ghost'));
    });
    bar.appendChild(actions);
    host.prepend(bar);
  }

  var originalAssignments = window.viewAssignments;
  var activeTaskFilter = 'To do';
  var activeTaskQuery = '';
  var selectedTask = null;
  function loadTaskProgress() { var p = getJson(key('task_progress'), {}); return p && typeof p === 'object' && !Array.isArray(p) ? p : {}; }
  function storeTaskProgress(p) { setJson(key('task_progress'), p); }
  // Progress is written to the same Supabase RPC as the native Flutter app.
  // Keep local-first values until the server confirms them, and retry on reconnect.
  var taskProgressSyncFlights = Object.create(null);
  var taskProgressSyncTimer = null;
  function syncTaskProgress(assignmentId) {
    var k = String(assignmentId == null ? '' : assignmentId);
    if (!/^\d+$/.test(k) || Number(k) < 1) return Promise.resolve(false);
    if (window.navigator.onLine === false || !window.SP_LMS || typeof window.SP_LMS.rpc !== 'function') return Promise.resolve(false);
    if (role() !== 'student' || !profile().approved) return Promise.resolve(false);
    if (taskProgressSyncFlights[k]) return taskProgressSyncFlights[k];
    var run = (async function () {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (window.navigator.onLine === false) return false;
        var all = loadTaskProgress();
        var p = all[k];
        if (!p || p.submitted) return false;
        var target = taskTarget(p);
        var done = Math.min(target, Math.max(0, Math.floor(Number(p.done) || 0)));
        var correct = Math.min(done, Math.max(0, Math.floor(Number(p.correct) || 0)));
        if (done < 1) return true;
        var sentDone = Number(p.serverSyncedDone);
        var sentCorrect = Number(p.serverSyncedCorrect);
        if (Number.isFinite(sentDone) && sentDone >= done && Number.isFinite(sentCorrect) && sentCorrect >= correct) return true;
        await window.SP_LMS.rpc('update_assignment_progress', {
          p_assignment: Number(k), p_done: done, p_correct: correct
        });
        // Another answer may have been recorded while the request was in flight.
        // Mark only the snapshot just acknowledged; loop to send any newer snapshot.
        all = loadTaskProgress();
        p = all[k];
        if (!p) return true;
        p.serverSyncedDone = Math.max(Number(p.serverSyncedDone) || 0, done);
        p.serverSyncedCorrect = Math.max(Number(p.serverSyncedCorrect) || 0, correct);
        p.serverSyncedAt = new Date().toISOString();
        storeTaskProgress(all);
        var latestDone = Math.min(target, Math.max(0, Math.floor(Number(p.done) || 0)));
        var latestCorrect = Math.min(latestDone, Math.max(0, Math.floor(Number(p.correct) || 0)));
        if (latestDone === done && latestCorrect === correct) return true;
      }
      return false;
    })().catch(function () {
      // The local snapshot is intentionally retained; online / route retries will resend it.
      return false;
    });
    taskProgressSyncFlights[k] = run;
    run.then(function () {
      if (taskProgressSyncFlights[k] === run) delete taskProgressSyncFlights[k];
    });
    return run;
  }
  function syncPendingTaskProgress() {
    if (role() !== 'student' || !profile().approved || window.navigator.onLine === false) return;
    var all = loadTaskProgress();
    Object.keys(all).forEach(function (k) {
      var p = all[k] || {};
      if (p.submitted) return; // Written tasks use the secure submit_progress review queue.
      var done = Math.max(0, Number(p.done) || 0);
      var correct = Math.max(0, Number(p.correct) || 0);
      if (done > (Number(p.serverSyncedDone) || 0) || correct > (Number(p.serverSyncedCorrect) || 0)) {
        syncTaskProgress(k);
      }
    });
  }
  function scheduleTaskProgressSync(assignmentId) {
    clearTimeout(taskProgressSyncTimer);
    taskProgressSyncTimer = setTimeout(function () { syncTaskProgress(assignmentId); }, 500);
  }
  function beginTaskPractice(t) {
    var all = loadTaskProgress();
    var k = taskId(t);
    var old = all[k] || {};
    var target = taskTarget(t);
    var serverDone = Math.min(target, Math.max(0, Number(t.done) || Number(t.completed_count) || 0));
    var serverCorrect = Math.min(serverDone, Math.max(0, Number(t.correct) || 0));
    var done = Math.min(target, Math.max(Number(old.done) || 0, serverDone));
    var correct = Math.min(done, Math.max(Number(old.correct) || 0, serverCorrect));
    var p = Object.assign({}, old, {
      assignment_id: k, title: taskTitle(t), skill: String(t.skill || t.kind || 'mixed'),
      done: done, correct: correct, target_count: target, updated_at: new Date().toISOString()
    });
    p.serverSyncedDone = Math.max(Number(old.serverSyncedDone) || 0, serverDone);
    p.serverSyncedCorrect = Math.max(Number(old.serverSyncedCorrect) || 0, serverCorrect);
    all[k] = p;
    storeTaskProgress(all);
    setJson(key('task_active'), {
      assignment_id: k, title: taskTitle(t), skill: String(t.skill || t.kind || 'mixed'),
      target_count: target, done: done, correct: correct
    });
  }
  function taskId(t) { return String(t && t.id != null ? t.id : t && t.assignment_id != null ? t.assignment_id : ''); }
  function taskTitle(t) { return String(t && (t.title || t.name) || 'Assignment'); }
  function taskTarget(t) { var n = Number(t && (t.target_count || t.targetCount)); return Number.isFinite(n) && n > 0 ? Math.min(1000, Math.floor(n)) : 10; }
  function taskDone(t) {
    var p = loadTaskProgress()[taskId(t)] || {};
    var serverDone = Number(t && (t.done || t.completed_count)) || 0;
    return Math.max(serverDone, Number(p.done) || 0);
  }
  function isTaskWriting(t) { return String(t && (t.skill || t.kind) || '').toLowerCase().indexOf('writ') >= 0; }
  function taskRows(data) {
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.assignments)) return data.assignments;
    if (data && data.data && Array.isArray(data.data.assignments)) return data.data.assignments;
    return [];
  }
  function queueTaskWriting(t, text) {
    var queue = getJson(key('task_submissions'), []);
    if (!Array.isArray(queue)) queue = [];
    var id = (window.crypto && window.crypto.randomUUID) ? window.crypto.randomUUID() : 'task-' + Date.now() + '-' + Math.random().toString(36).slice(2,10);
    var clean = String(text || '').trim().slice(0,2500);
    if (!clean) throw new Error('Write your answer before submitting.');
    queue.push({id:id,client_id:id,assignment_id:taskId(t),title:taskTitle(t),level:String(t.level || ''),t:new Date().toISOString(),words:clean.split(/\s+/).filter(Boolean).length,text:clean,score:0});
    setJson(key('task_submissions'), queue);
    var all = loadTaskProgress(); var k = taskId(t); var p = all[k] || {};
    all[k] = Object.assign({}, p, {assignment_id:k,title:taskTitle(t),skill:String(t.skill || t.kind || 'writing'),done:Math.max(Number(p.done)||0,1),correct:Number(p.correct)||0,target_count:taskTarget(t),submitted:true,completed:true,updated_at:new Date().toISOString()});
    storeTaskProgress(all);
    // Mark the study state dirty so queued work is retried after connectivity returns.
    try { if (typeof STORE !== 'undefined' && STORE && typeof STORE.save === 'function') STORE.save(); } catch (_) {}
    return queue.length;
  }
  function taskDetails(host, t, onBack) {
    host.replaceChildren();
    heading(host, taskTitle(t), String(t.instructions || t.description || 'Complete this task and keep your work saved on this device.'), 'TASK');
    var c = node('section', 'fp-card fp-task-card');
    var meta = node('div', 'fp-task-meta');
    meta.appendChild(node('span','fp-pill',String(t.skill || t.kind || 'Mixed')));
    if (t.due_at || t.dueAt) meta.appendChild(node('span','fp-pill','Due ' + new Date(t.due_at || t.dueAt).toLocaleDateString()));
    meta.appendChild(node('span','fp-pill',taskDone(t) + ' / ' + taskTarget(t) + ' complete'));
    c.appendChild(meta);
    c.appendChild(node('p','fp-muted',String(t.instructions || t.description || '')));
    if (isTaskWriting(t)) {
      var drafts = getJson(key('task_drafts'), {});
      var area = node('textarea','', '');
      area.setAttribute('aria-label','Your assignment response');
      area.placeholder = 'Write your German answer here…';
      area.value = String(drafts[taskId(t)] || '');
      area.addEventListener('input', function () {
        var latest = getJson(key('task_drafts'), {}); latest[taskId(t)] = area.value.slice(0,2500); setJson(key('task_drafts'),latest);
      });
      c.appendChild(area);
      c.appendChild(button('Save draft', function () {
        var latest = getJson(key('task_drafts'), {}); latest[taskId(t)] = area.value.slice(0,2500); setJson(key('task_drafts'),latest);
        c.appendChild(node('p','fp-muted','Draft saved on this device.'));
      }, 'btn ghost'));
      c.appendChild(button('Submit for teacher review', async function (e) {
        var submit = e.currentTarget; submit.disabled = true;
        try {
          queueTaskWriting(t, area.value);
          var message = node('div','fp-note','Saved on this device. It will be sent with your next progress sync.');
          c.appendChild(message);
          if (window.navigator.onLine && window.SP_AUTH && window.SP_AUTH.syncNow) {
            try { var result = await window.SP_AUTH.syncNow(true); if (result && result.ok) message.textContent = 'Submitted for teacher review.'; }
            catch (_) { message.textContent = 'Saved offline. It will be sent when sync succeeds.'; }
          }
        } catch (error) { c.appendChild(node('div','fp-note',error.message || 'Could not save this response.')); }
        finally { submit.disabled = false; }
      }, 'btn'));
      var queue = getJson(key('task_submissions'),[]);
      var waiting = Array.isArray(queue) ? queue.filter(function (q) { return String(q.assignment_id) === taskId(t); }).length : 0;
      if (waiting) c.appendChild(node('p','fp-muted',waiting + ' response(s) waiting for sync or review.'));
    } else {
      var text = node('p','fp-muted','Progress is saved on this device first and synced to your classroom whenever a connection is available.');
      c.appendChild(text);
      c.appendChild(button('Start practice', function () {
        beginTaskPractice(t);
        go('practice');
      }, 'btn'));
    }
    c.appendChild(button('Back to task list', onBack, 'btn ghost'));
    host.appendChild(c);
    host.appendChild(node('p','fp-muted','Practice progress syncs to your classroom when online. Work completed offline stays saved here and retries automatically after reconnecting.'));
  }
  function viewFlutterAssignments(host) {
    appendStyles();
    if (role() === 'teacher' || role() === 'admin') {
      if (typeof originalAssignments === 'function' && originalAssignments !== viewFlutterAssignments) return originalAssignments(host);
      host.replaceChildren(); heading(host,'Work','Teacher and admin assignment workspace.','STAFF');
      host.appendChild(node('div','fp-note','Assignment publishing needs the classroom LMS schema to be present in the connected database.'));
      return;
    }
    var query = activeTaskQuery;
    function render(rows, errorText) {
      if (!host.isConnected && document.getElementById('view') !== host) return;
      host.replaceChildren();
      heading(host,'Tasks','Assignments and written responses from your teacher.','STUDENT');
      var filters = node('div','fp-filter');
      ['To do','Done','All'].forEach(function (filter) {
        var b = button(filter,function(){activeTaskFilter=filter;render(rows,errorText);},activeTaskFilter===filter?'active':'');
        if(activeTaskFilter===filter)b.classList.add('active');
        filters.appendChild(b);
      });
      host.appendChild(filters);
      var search = node('input','fp-search');
      search.type='search';search.placeholder='Search assignments…';search.value=query;search.setAttribute('aria-label','Search assignments');
      search.addEventListener('input',function(){var cursor=search.selectionStart;activeTaskQuery=search.value;query=activeTaskQuery;render(rows,errorText);var next=host.querySelector('.fp-search');if(next){next.focus();try{next.setSelectionRange(cursor,cursor);}catch(_){}}});
      host.appendChild(search);
      var actions=node('div','fp-actions');
      actions.appendChild(button('Practice independently',function(){go('practice');},'btn ghost'));
      actions.appendChild(button('Open Learn',function(){go('learn');},'btn ghost'));
      host.appendChild(actions);
      if(errorText)host.appendChild(node('div','fp-note',errorText));
      var progress=loadTaskProgress();
      var visible=(rows||[]).filter(function(t){
        var done=taskDone(t),target=taskTarget(t),isDone=!!(progress[taskId(t)]&&progress[taskId(t)].submitted)||done>=target;
        var status=activeTaskFilter==='All'||(activeTaskFilter==='Done'?isDone:!isDone);
        return status&&(!query||taskTitle(t).toLowerCase().includes(query.toLowerCase())||String(t.instructions||'').toLowerCase().includes(query.toLowerCase()));
      });
      if(!visible.length){
        host.appendChild(node('div','fp-empty',errorText?'Your offline learning tools still work. Tasks will appear here when the classroom backend is available.':'No tasks match this filter yet. You can continue learning while you wait for a task.'));
        return;
      }
      visible.forEach(function(t){
        var c=node('section','fp-card fp-task-card');
        var title=node('h3','',taskTitle(t));c.appendChild(title);
        var meta=node('div','fp-task-meta');
        meta.appendChild(node('span','fp-pill',String(t.skill||t.kind||'Mixed')));
        if(t.class_name||t.className)meta.appendChild(node('span','fp-pill',String(t.class_name||t.className)));
        if(t.due_at||t.dueAt){var date=new Date(t.due_at||t.dueAt);meta.appendChild(node('span','fp-pill','Due '+(isNaN(date.getTime())?'date set':date.toLocaleDateString())));}
        c.appendChild(meta);
        var done=taskDone(t),target=taskTarget(t);
        c.appendChild(node('p','fp-muted',String(t.instructions||t.description||'No extra instructions.')));
        c.appendChild(node('p','fp-muted',done+' / '+target+' completed'));
        var track=node('div','fp-progress');var fill=node('i');fill.style.width=Math.min(100,Math.round(done/Math.max(1,target)*100))+'%';track.appendChild(fill);c.appendChild(track);
        var act=node('div','fp-actions');
        act.appendChild(button(isTaskWriting(t)?'Open writing task':'Start practice',function(){selectedTask=t;taskDetails(host,t,function(){viewFlutterAssignments(host);});},'btn'));
        act.appendChild(button('Details',function(){selectedTask=t;taskDetails(host,t,function(){viewFlutterAssignments(host);});},'btn ghost'));
        c.appendChild(act);host.appendChild(c);
      });
    }
    host.replaceChildren();heading(host,'Tasks','Loading assignments…','STUDENT');
    if(!window.SP_LMS||!window.SP_LMS.rpc){render([],null);return;}
    window.SP_LMS.rpc('my_classroom').then(function(data){render(taskRows(data),null);}).catch(function(){
      render([],'Class assignment data is not available in the connected database yet. Your practice and written drafts still work locally; ask an administrator to finish the classroom database setup.');
    });
  }

  function viewFlutterDashboard(host) {
    appendStyles();
    if (role() === 'student') { viewFlutterHome(host); return; }
    host.replaceChildren();
    var isAdmin = role() === 'admin';
    heading(host,isAdmin?'Admin dashboard':'Teacher dashboard',isAdmin?'Monitor approvals and submitted progress, then open the management tools.':'Open your classes, student progress, assignments and class news.',isAdmin?'ADMIN':'TEACHER');
    var shortcuts=grid(host);
    var items=isAdmin?[
      ['👤','Students','Approve accounts and review student progress','students'],
      ['🛡️','Admin tools','Classes, assignments, roles and submission review','admin'],
      ['👨‍🏫','Teachers','Manage teacher assignments','teachers'],
      ['📝','Assignments','Create and track practice work','assignments'],
      ['👥','Classes','Browse classroom groups','classroom'],
      ['📢','News','Publish class announcements','announcements'],
      ['🔔','Notifications','Open the notification inbox','notifications'],
      ['🧾','Audit','Staff and student activity','audit']
    ]:[
      ['📝','Work','Assignments and submission progress','assignments'],
      ['👥','Classes','Your class list','classroom'],
      ['👤','Students','Students assigned to you','students'],
      ['📢','News','Announcements for your classes','announcements'],
      ['🔔','Notifications','Open the notification inbox','notifications']
    ];
    items.forEach(function(x){linkCard(shortcuts,x[1],x[2],x[3],x[0]);});
    var metrics=node('div','fp-overview');metrics.appendChild(node('h3','',isAdmin?'Overview':'Classroom status'));
    var stats=node('div','fp-mini-grid');
    var m1=node('div','fp-mini');m1.appendChild(node('b','','—'));m1.appendChild(node('span','',isAdmin?'Student accounts':'Assigned students'));stats.appendChild(m1);
    var m2=node('div','fp-mini');m2.appendChild(node('b','','—'));m2.appendChild(node('span','',isAdmin?'Pending review':'Classes'));stats.appendChild(m2);
    metrics.appendChild(stats);host.appendChild(metrics);
    if(isAdmin&&window.SP_LMS&&window.SP_LMS.api){
      Promise.all([
        window.SP_LMS.api('/rest/v1/profiles?select=id,role,approved&order=created_at.desc&limit=500'),
        window.SP_LMS.api('/rest/v1/submissions?select=id,student_id,created_at,review_status,summary,review_note,rating&order=created_at.desc&limit=100')
      ]).then(function(result){
        var profiles=Array.isArray(result[0])?result[0]:[];
        var submissions=Array.isArray(result[1])?result[1]:[];
        m1.firstChild.textContent=String(profiles.filter(function(p){return p.role==='student';}).length);
        m2.firstChild.textContent=String(profiles.filter(function(p){return p.role==='student'&&!p.approved;}).length)+' pending';
        var review=node('section','fp-card');review.appendChild(node('h3','','Recent progress reports'));
        var pending=submissions.filter(function(s){return s.review_status==='pending';});
        review.appendChild(node('p','fp-muted',pending.length+' reports waiting for review. Open Admin tools to review reports and return feedback.'));
        review.appendChild(button('Review submissions',function(){go('admin');},'btn'));
        metrics.appendChild(review);
      }).catch(function(){
        metrics.appendChild(node('p','fp-muted','Live metrics will load when administrator read access is available.'));
      });
    } else if(window.SP_LMS&&window.SP_LMS.rpc){
      Promise.all([window.SP_LMS.rpc('my_classroom'),window.SP_LMS.rpc('my_students')]).then(function(result){
        var classroom=result[0]||{};var students=Array.isArray(result[1])?result[1]:[];
        m1.firstChild.textContent=String(students.length);
        m2.firstChild.textContent=String(Array.isArray(classroom.classes)?classroom.classes.length:0);
      }).catch(function(){
        metrics.appendChild(node('p','fp-muted','Your classroom data will appear here when your teacher workspace is enabled in the connected database.'));
      });
    } else metrics.appendChild(node('p','fp-muted','Sign in to load role-specific workspace data.'));
  }

  function setupNotificationButton() {
    if (!window.SP_LMS || !window.SP_LMS.api) return;
    var header=document.querySelector('header');
    if(!header)return;
    var b=document.getElementById('spNotifications');
    if(!b){
      b=node('button','iconbtn fp-notify','🔔');
      b.id='spNotifications';b.type='button';b.title='Notifications';b.setAttribute('aria-label','Notifications');
      b.appendChild(node('span','fp-notify-count',''));b.lastChild.hidden=true;
      b.addEventListener('click',function(){go('notifications');});
      var account=document.getElementById('spAcct');var settings=document.getElementById('settingsBtn');
      if(account&&account.parentNode===header)header.insertBefore(b,account);
      else if(settings&&settings.parentNode===header)header.insertBefore(b,settings);
      else header.appendChild(b);
    }
    var badge=b.querySelector('.fp-notify-count');
    function update(){
      if(!document.getElementById('spNotifications'))return;
      window.SP_LMS.notificationCount().then(function(rows){
        var count=Array.isArray(rows)?rows.filter(function(item){return !item.read_at;}).length:0;
        badge.textContent=count>99?'99+':String(count);badge.hidden=count===0;
        b.title=count?count+' unread notifications':'Notifications';
        b.setAttribute('aria-label',b.title);
      }).catch(function(){badge.hidden=true;});
    }
    update();
    if(!window.__spFlutterNotifyTimer)window.__spFlutterNotifyTimer=setInterval(update,30000);
  }

  // Attribute real practice answers to the active assignment. The same cumulative progress
  // is sent to update_assignment_progress in Flutter and on web; failed calls remain queued.
  if(typeof window.recordPracticeActivity==='function'&&!window.recordPracticeActivity.__spFlutterWrapped){
    var originalRecorder=window.recordPracticeActivity;
    var wrappedRecorder=function(skill,correct){
      var result=originalRecorder.apply(this,arguments);
      var active=getJson(key('task_active'),null);
      if(active&&active.assignment_id){
        var progress=loadTaskProgress();var k=String(active.assignment_id);var p=progress[k]||{};
        var target=Math.max(1,Math.min(1000,Number(p.target_count||active.target_count)||10));
        var previousDone=Math.max(Number(p.done)||0,Number(active.done)||0);
        var previousCorrect=Math.max(Number(p.correct)||0,Number(active.correct)||0);
        var done=Math.min(target,previousDone+1);
        var good=Math.min(done,previousCorrect+(correct===true?1:0));
        progress[k]=Object.assign({},p,{assignment_id:k,title:active.title||'Assignment',skill:String(active.skill||skill||'mixed'),done:done,correct:good,target_count:target,completed:done>=target,submitted:!!p.submitted,updated_at:new Date().toISOString()});
        storeTaskProgress(progress);
        scheduleTaskProgressSync(k);
        if(done>=target)try{localStorage.removeItem(key('task_active'));}catch(_){}
        var badge=document.querySelector('[data-active-task-progress]');
        if(badge)badge.textContent=done+' / '+target+' questions';
      }
      return result;
    };
    wrappedRecorder.__spFlutterWrapped=true;
    window.recordPracticeActivity=wrappedRecorder;
  }
  window.addEventListener('online',syncPendingTaskProgress);
  window.addEventListener('hashchange',function(){setTimeout(syncPendingTaskProgress,0);});
  setTimeout(syncPendingTaskProgress,0);
  if(!window.__spTaskProgressRetryTimer)window.__spTaskProgressRetryTimer=setInterval(syncPendingTaskProgress,30000);

  window.viewFlutterHome=viewFlutterHome;
  window.viewFlutterLearn=viewFlutterLearn;
  window.viewFlutterCourse=viewFlutterCourse;
  window.viewFlutterPractice=viewFlutterPractice;
  window.viewFlutterDashboard=viewFlutterDashboard;
  window.viewAssignments=viewFlutterAssignments;
  appendStyles();
  setupNotificationButton();
  if ((location.hash||'#/home')==='#/home' && document.getElementById('view') && !document.body.classList.contains('sp-locked')) {
    try { viewFlutterHome(document.getElementById('view')); } catch (_) {}
  }
})();