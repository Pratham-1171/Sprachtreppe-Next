/* Source module: views-learning.js
 * Main learning screens.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
function viewHome(el){
  const total = VOCAB.length;
  const mastered = Object.keys(S.mastery).filter(k => k.startsWith('v') && (S.mastery[k].status === 'MASTERED' || S.mastery[k].status === 'STRONG')).length;
  const due = dueCount();
  const streak = S.streak.current;
  const dailyGoal = S.settings.dailyGoal || 20;
  const todayDone = S.sessionHistory.filter(s => s.date === new Date().toISOString().slice(0,10)).reduce((a,b) => a + b.questions, 0);
  const goalPct = Math.min(100, pct(todayDone, dailyGoal));
  const mistakeCount = Object.keys(S.mistakes).length;
  el.innerHTML = `
    <div class="today-dash">
      <div class="streak-badge">🔥 ${streak} ${t('stat_streak')}</div>
      <h3>${t('home_title')}</h3>
      <div class="td-sub">${t('home_desc')}</div>
      <div style="font-size:12.5px;opacity:.9;margin-bottom:6px">Today: ${todayDone} / ${dailyGoal}</div>
      <div class="goal-bar"><i style="width:${goalPct}%"></i></div>
      <div class="td-stats">
        <span>📚 ${mastered}/${total}</span>
        <span>🧠 ${due} ${t('stat_due')}</span>
        <span>❌ ${mistakeCount}</span>
      </div>
    </div>
    <div class="row" style="margin-bottom:14px">
      <button class="btn grow" id="quickStart">⚡ ${t('session_start')}</button>
      <button class="btn ghost" id="quickReview">🧠 ${t('review_start')}</button>
    </div>
    <h3>${t('study_modules')}</h3>
    <div class="grid">
      <button class="tile" data-go="session"><span class="t-ico">⚡</span><span class="t-name">Session</span><span class="t-desc">Infinite guided</span></button>
      <button class="tile" data-go="review"><span class="t-ico">🧠</span><span class="t-name">Smart Review</span><span class="t-desc">Due + mistakes</span></button>
      <button class="tile" data-go="vocab"><span class="t-ico">📚</span><span class="t-name">Vocabulary</span><span class="t-desc">${total} words</span></button>
      <button class="tile" data-go="grammar"><span class="t-ico">📖</span><span class="t-name">Grammar</span><span class="t-desc">A1 / A2 / B1</span></button>
      <button class="tile" data-go="quiz"><span class="t-ico">🎯</span><span class="t-name">Quiz</span><span class="t-desc">Infinite modes</span></button>
      <button class="tile" data-go="verbs"><span class="t-ico">🔥</span><span class="t-name">Verbs</span><span class="t-desc">Usage + freq</span></button>
      <button class="tile" data-go="connectors"><span class="t-ico">🔗</span><span class="t-name">Connectors</span><span class="t-desc">${CONNECTORS.length} rules</span></button>
      <button class="tile" data-go="collocations"><span class="t-ico">🧱</span><span class="t-name">Collocations</span><span class="t-desc">${COLLOCATIONS.length} phrases</span></button>
      <button class="tile" data-go="compare"><span class="t-ico">⚖️</span><span class="t-name">Verb Compare</span><span class="t-desc">${VERB_COMPARISONS.length} pairs</span></button>
      <button class="tile" data-go="flash"><span class="t-ico">🧠</span><span class="t-name">Flashcards</span><span class="t-desc">SRS</span></button>
      <button class="tile" data-go="mistakes"><span class="t-ico">❌</span><span class="t-name">Mistakes</span><span class="t-desc">${mistakeCount}</span></button>
      <button class="tile" data-go="sentence"><span class="t-ico">🧩</span><span class="t-name">Sentences</span><span class="t-desc">Infinite</span></button>
      <button class="tile" data-go="spelling"><span class="t-ico">✏️</span><span class="t-name">Spelling</span><span class="t-desc">Infinite</span></button>
      <button class="tile" data-go="dictation"><span class="t-ico">📝</span><span class="t-name">Dictation</span><span class="t-desc">Infinite</span></button>
      <button class="tile" data-go="families"><span class="t-ico">🌳</span><span class="t-name">Word Families</span><span class="t-desc">${WORD_FAMILIES.length}</span></button>
      <button class="tile" data-go="listen"><span class="t-ico">🎧</span><span class="t-name">Listening</span><span class="t-desc">Generated ∞</span></button>
      <button class="tile" data-go="speak"><span class="t-ico">🎤</span><span class="t-name">Speaking</span><span class="t-desc">Generated ∞</span></button>
      <button class="tile" data-go="read"><span class="t-ico">📕</span><span class="t-name">Reading</span><span class="t-desc">Generated ∞</span></button>
      <button class="tile" data-go="write"><span class="t-ico">✍️</span><span class="t-name">Writing</span><span class="t-desc">Generated ∞</span></button>
      <button class="tile" data-go="exam"><span class="t-ico">🎓</span><span class="t-name">Exam</span><span class="t-desc">Timed</span></button>
      <button class="tile" data-go="progress"><span class="t-ico">📊</span><span class="t-name">Progress</span><span class="t-desc">Statistics</span></button>
      <button class="tile" data-go="settings"><span class="t-ico">⚙️</span><span class="t-name">Settings</span><span class="t-desc">Preferences</span></button>
    </div>`;
  el.querySelectorAll('[data-go]').forEach(b => b.onclick = () => location.hash = '#/' + b.dataset.go);
  $('#quickStart').onclick = () => location.hash = '#/session';
  $('#quickReview').onclick = () => location.hash = '#/review';
}

/* ============================================================
   SESSION
   ============================================================ */
let sessionState = {active:false, results:[], startTime:0, queue:[], idx:0, total:0};

function viewSession(el){
  if(sessionState.active){ renderSessionCard(el); return; }
  el.innerHTML = `<h2>${t('session_title')}</h2><p class="sub">Infinite guided mix of review + practice.</p>
    <div class="card"><h4 style="margin-top:0">Session length</h4>
      <div class="chipgroup">${[10,15,30,45].map(n => `<button data-len="${n}" class="${(S.settings.sessionLen||15)===n?'active':''}">${n} min</button>`).join('')}</div>
    </div>
    <div class="card"><h4 style="margin-top:0">Preview</h4>
      <div class="mini-muted" style="line-height:1.8">
        🎯 Warm-up review<br>
        🧠 Due vocabulary (${dueCount()})<br>
        ❌ Mistake practice (${Object.keys(S.mistakes).length})<br>
        📚 New words · 📖 Grammar · 🎧 Listening · 🎤 Speaking
      </div>
    </div>
    <button class="btn" id="startSession" style="width:100%">${t('session_start')}</button>`;
  el.querySelectorAll('[data-len]').forEach(b => b.onclick = () => {
    S.settings.sessionLen = parseInt(b.dataset.len, 10); STORE.save();
    el.querySelectorAll('[data-len]').forEach(x => x.classList.remove('active'));
    b.classList.add('active');
  });
  $('#startSession').onclick = () => {
    sessionState = {active:true, results:[], startTime:Date.now(), queue:[], idx:0, total:0};
    // Build a mix: 5 due, 3 mistakes, 5 new, 3 grammar, 1 listening, 1 speaking
    const dueWords = dueWordKeys().map(k => VOCAB.find(w => 'v'+w.n === k)).filter(Boolean);
    const mistakes = Object.values(S.mistakes).sort((a,b) => b.count - a.count);
    const queue = [];
    const warm = dueWords.length ? dueWords.slice(0, 5) : shuffle(VOCAB).slice(0, 5);
    warm.forEach(w => queue.push({kind:'vocab', w}));
    mistakes.slice(0, 3).forEach(m => queue.push({kind:'mistake', m}));
    shuffle(VOCAB.filter(w => !S.mastery['v'+w.n] || S.mastery['v'+w.n].status === 'NEW')).slice(0, 5).forEach(w => queue.push({kind:'vocab', w}));
    for(let i = 0; i < 3; i++) queue.push({kind:'generated', ex: generateExercise({skill:'mixed', level:'A2', difficulty:'mixed'})});
    queue.push({kind:'generated', ex: generateExercise({skill:'listening', level:'A2', difficulty:'normal'})});
    queue.push({kind:'generated', ex: generateExercise({skill:'sentence', level:'A2', difficulty:'normal'})});
    sessionState.queue = shuffle(queue);
    sessionState.total = queue.length;
    renderSessionCard(el);
  };
}

function renderSessionCard(el){
  if(sessionState.idx >= sessionState.total){ renderSessionSummary(el); return; }
  const item = sessionState.queue[sessionState.idx];
  el.innerHTML = `<div class="session-progress">${Array.from({length: sessionState.total}, (_, i) =>
    `<div class="sp-dot ${i < sessionState.idx ? 'done' : i === sessionState.idx ? 'current' : ''}"></div>`).join('')}</div>
    <div style="font-size:12px;color:var(--muted);margin-bottom:8px">Step ${sessionState.idx+1} of ${sessionState.total} · ${item.kind}</div>
    <div id="sessionBody"></div>`;
  const body = $('#sessionBody');
  if(item.kind === 'vocab'){
    const w = item.w;
    const ex = generateVocabExercise('de-en', [w, ...shuffle(VOCAB).slice(0,20)]);
    renderSessionExercise(body, ex, w);
  } else if(item.kind === 'mistake'){
    const m = item.m;
    body.innerHTML = `<div class="session-card"><div class="sc-type">Mistake review</div>
      <div style="font-size:15px;margin:8px 0">${esc(m.prompt)}</div>
      <div class="mini-muted">Your last: <span style="color:var(--warn)">${esc(m.userAnswer)}</span></div>
      <div class="mini-muted">Correct: <span style="color:var(--ok)">${esc(m.correctAnswer)}</span></div>
      <div class="mini-muted" style="margin-top:6px">${esc(m.explanation||'')}</div>
      <div class="row" style="margin-top:10px"><button class="btn good" id="sOk">✓ Got it</button></div></div>`;
    $('#sOk').onclick = () => {
      sessionState.results.push({correct:true}); sessionState.idx++;
      addStudyTime(20); renderSessionCard(el);
    };
  } else if(item.kind === 'generated'){
    renderSessionExercise(body, item.ex, null);
  }
}

function renderSessionExercise(body, ex, w){
  body.innerHTML = `<div class="session-card">
    <div class="sc-type">${ex.skill || 'practice'}</div>
    <div style="font-size:16px;margin:8px 0;line-height:1.5">${ex.promptHTML}</div>
    <div id="sOpts">${ex.options.map(o => `<button class="opt" data-v="${esc(o)}">${esc(o)}</button>`).join('')}</div>
    <div class="fb" style="margin-top:10px;font-size:13px"></div>
  </div>`;
  wireSpeakers(body);
  if(ex.autoPlay) speakGerman(ex.autoPlay);
  const fb = body.querySelector('.fb');
  body.querySelectorAll('.opt').forEach(b => b.onclick = () => {
    if(body.dataset.done) return;
    body.dataset.done = '1';
    const ok = b.dataset.v === ex.correct;
    body.querySelectorAll('.opt').forEach(x => { x.disabled = true; if(x.dataset.v === ex.correct) x.classList.add('correct'); else if(x === b) x.classList.add('wrong'); });
    fb.textContent = (ok ? '✅ ' : '❌ Correct: ' + ex.correct + '. ') + (ex.explanation || '');
    fb.style.color = ok ? 'var(--ok)' : 'var(--warn)';
    if(w) updateMastery(vocabKey(w), ok ? 2 : 0);
    if(!ok) recordMistake({type:'session', topic:ex.topic||ex.skill, prompt:ex.prompt, userAnswer:b.dataset.v, correctAnswer:ex.correct, explanation:ex.explanation, sourceId:ex.sourceId});
    sessionState.results.push({correct:ok});
    addStudyTime(15);
    setTimeout(() => { sessionState.idx++; renderSessionCard($('#view')); }, 900);
  });
}

function renderSessionSummary(el){
  const total = sessionState.results.length;
  const correct = sessionState.results.filter(r => r.correct).length;
  const accuracy = pct(correct, total);
  const duration = Math.floor((Date.now() - sessionState.startTime) / 1000);
  S.studyTime.sessions = (S.studyTime.sessions || 0) + 1;
  S.sessionHistory.push({id:'web-session:' + courseUuid(), date:new Date().toISOString().slice(0,10), questions:total, correct, duration});
  if(S.sessionHistory.length > 200) S.sessionHistory = S.sessionHistory.slice(-200);
  touchStreak(); STORE.save(); checkAchievements();
  sessionState.active = false;
  el.innerHTML = `<h2>${t('session_complete')}</h2>
    <div class="card" style="text-align:center"><div style="font-size:44px;font-weight:800;color:var(--accent)">${accuracy}%</div><div class="mini-muted">Accuracy</div></div>
    <div class="stats">
      <div class="stat"><div class="n">${correct}/${total}</div><div class="l">Correct</div></div>
      <div class="stat"><div class="n">${Math.floor(duration/60)}:${String(duration%60).padStart(2,'0')}</div><div class="l">Time</div></div>
      <div class="stat"><div class="n">${Object.keys(S.mistakes).length}</div><div class="l">Mistakes</div></div>
    </div>
    <div class="row"><button class="btn" id="toReview">Review mistakes</button><button class="btn ghost" id="finish">Finish</button></div>`;
  $('#toReview').onclick = () => location.hash = '#/review';
  $('#finish').onclick = () => location.hash = '#/home';
}

/* ============================================================
   REVIEW / MISTAKES
   ============================================================ */
function viewReview(el){
  const due = dueWordKeys().map(k => VOCAB.find(w => 'v'+w.n === k)).filter(Boolean);
  const mistakes = Object.values(S.mistakes).sort((a,b) => b.count - a.count).slice(0, 10);
  const weak = VOCAB.filter(w => { const m = S.mastery['v'+w.n]; return m && (m.status === 'LEARNING' || m.status === 'FAMILIAR'); }).slice(0, 10);
  el.innerHTML = `<h2>${t('review_title')}</h2><p class="sub">Due cards, mistakes, weak areas.</p>
    <button class="btn" id="startReview" style="width:100%;margin-bottom:14px">${t('review_start')}</button>
    <h3>Due today (${due.length})</h3>
    <div class="card">${due.length ? `<div class="vlist">${due.slice(0, 6).map(w => vocabRowHTML(w)).join('')}</div>` : `<div class="empty">Nothing due — great!</div>`}</div>
    <h3>Top mistakes (${mistakes.length})</h3>
    <div class="card">${mistakes.length ? mistakes.slice(0, 4).map(m => mistakeCardHTML(m)).join('') : `<div class="empty">${t('mistakes_empty')}</div>`}</div>
    <h3>Weak words (${weak.length})</h3>
    <div class="card">${weak.length ? `<div class="vlist">${weak.slice(0, 4).map(w => vocabRowHTML(w)).join('')}</div>` : `<div class="empty">—</div>`}</div>`;
  wireSpeakers(el);
  el.querySelectorAll('.bookmark').forEach(b => {
    b.onclick = e => { e.stopPropagation(); const n = b.dataset.n; if(S.bookmarked[n]) delete S.bookmarked[n]; else S.bookmarked[n] = 1; STORE.save(); b.classList.toggle('on'); b.textContent = S.bookmarked[n] ? '★' : '☆'; };
  });
  $('#startReview').onclick = () => {
    sessionState = {active:true, results:[], startTime:Date.now(), queue:[], idx:0, total:0};
    const queue = [];
    due.slice(0, 10).forEach(w => queue.push({kind:'vocab', w}));
    weak.slice(0, 5).forEach(w => queue.push({kind:'vocab', w}));
    mistakes.slice(0, 5).forEach(m => queue.push({kind:'mistake', m}));
    sessionState.queue = queue.length ? queue : shuffle(VOCAB).slice(0, 10).map(w => ({kind:'vocab', w}));
    sessionState.total = sessionState.queue.length;
    location.hash = '#/session';
    setTimeout(() => { if(sessionState.active) renderSessionCard($('#view')); }, 50);
  };
}

function mistakeCardHTML(m){
  const key = m.type + '::' + (m.sourceId || m.prompt);
  return `<div class="mistake-card">
    <div class="mc-prompt">${esc(m.prompt)}</div>
    <div><span class="mc-user">Your: ${esc(m.userAnswer||'—')}</span></div>
    <div><span class="mc-correct">✓ ${esc(m.correctAnswer||'—')}</span></div>
    ${m.explanation ? `<div class="mini-muted" style="margin-top:4px">${esc(m.explanation)}</div>` : ''}
    <div class="mc-meta"><span>${esc(m.topic||m.type)}</span><span>× ${m.count}</span>
      <button class="btn small ghost" data-clear="${esc(key)}">Mark understood</button></div>
  </div>`;
}
function viewMistakes(el){
  const mistakes = Object.values(S.mistakes).sort((a,b) => b.count - a.count);
  el.innerHTML = `<h2>${t('mistakes_title')}</h2><p class="sub">Sorted by frequency.</p>
    ${mistakes.length ? `<button class="btn ghost" id="clearAll" style="margin-bottom:12px">🗑 Clear all</button>` : ''}
    <div>${mistakes.length ? mistakes.map(m => mistakeCardHTML(m)).join('') : `<div class="empty">${t('mistakes_empty')}</div>`}</div>`;
  el.querySelectorAll('[data-clear]').forEach(b => b.onclick = () => {
    clearMistake(b.dataset.clear); viewMistakes(el);
  });
  if($('#clearAll')) $('#clearAll').onclick = () => { clearAllMistakes(); viewMistakes(el); };
}

/* ============================================================
   VOCAB
   ============================================================ */
