/* Source module: views-vocabulary.js
 * Vocabulary, articles, flashcards, quizzes, verbs, pronunciation and word-reference screens.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
let vocabState = {q:'', topic:'all', art:'all', level:'all'};
function viewVocab(el){
  el.innerHTML = `<h2>📚 Vocabulary</h2><p class="sub">${VOCAB.length} words</p>
    <div class="card">
      <input type="search" id="vq" placeholder="${t('vocab_search')}" value="${esc(vocabState.q)}">
      <div class="row mt">
        <select id="vtopic" class="grow"><option value="all">${t('all_topics')}</option>${TOPIC_NAMES.map(x => `<option value="${esc(x)}" ${vocabState.topic===x?'selected':''}>${esc(x)}</option>`).join('')}</select>
        <select id="vart" style="width:auto"><option value="all">${t('all_articles')}</option><option value="der" ${vocabState.art==='der'?'selected':''}>der</option><option value="die" ${vocabState.art==='die'?'selected':''}>die</option><option value="das" ${vocabState.art==='das'?'selected':''}>das</option></select>
        <select id="vlevel" style="width:auto"><option value="all">${t('all_levels')}</option><option value="A1" ${vocabState.level==='A1'?'selected':''}>A1</option><option value="A2" ${vocabState.level==='A2'?'selected':''}>A2</option><option value="B1" ${vocabState.level==='B1'?'selected':''}>B1</option></select>
      </div>
      <div class="mt row" style="justify-content:space-between">
        <span style="font-size:13px;color:var(--muted)" id="vcount"></span>
        <button class="btn small ghost" id="playAll">🔊 Play first 10</button>
      </div>
    </div>
    <div id="vlist" class="vlist"></div>`;
  const q = $('#vq'), topicSel = $('#vtopic'), a = $('#vart'), l = $('#vlevel');
  let currentList = [];
  const render = () => {
    vocabState.q = q.value.trim().toLowerCase();
    vocabState.topic = topicSel.value; vocabState.art = a.value; vocabState.level = l.value;
    const list = VOCAB.filter(w => {
      if(vocabState.topic!=='all' && w.topic!==vocabState.topic) return false;
      if(vocabState.art!=='all' && w.art!==vocabState.art) return false;
      if(vocabState.level!=='all' && w.level!==vocabState.level) return false;
      if(vocabState.q){
        const s = vocabState.q;
        const syn = SYNONYMS.find(x => x.word === w.de);
        const synText = syn ? syn.syn.map(x => x[0]).join(' ') : '';
        const opp = OPPOSITES.filter(p => p[0] === w.de || p[2] === w.de).map(p => p.join(' ')).join(' ');
        const hay = [w.de, w.en, synText, opp].join(' ').toLowerCase();
        if(!hay.includes(s)) return false;
      }
      return true;
    });
    currentList = list;
    $('#vcount').textContent = `${list.length} shown`;
    const wrap = $('#vlist');
    if(!list.length){ wrap.innerHTML = `<div class="empty">${t('no_words')}</div>`; return; }
    wrap.innerHTML = list.slice(0, 400).map(w => vocabRowHTML(w)).join('') +
      (list.length > 400 ? `<div class="empty">Showing first 400 of ${list.length}.</div>` : '');
    wrap.querySelectorAll('.bookmark').forEach(b => {
      b.onclick = e => { e.stopPropagation(); const n = b.dataset.n; if(S.bookmarked[n]) delete S.bookmarked[n]; else S.bookmarked[n] = 1; STORE.save(); b.classList.toggle('on'); b.textContent = S.bookmarked[n] ? '★' : '☆'; };
    });
    wireSpeakers(wrap);
  };
  q.oninput = render; topicSel.onchange = render; a.onchange = render; l.onchange = render; render();
  $('#playAll').onclick = () => {
    const toPlay = currentList.slice(0, 10);
    if(!toPlay.length || !('speechSynthesis' in window)) return;
    speechSynthesis.cancel();
    toPlay.forEach(w => {
      const text = (w.art && w.art !== '-' ? w.art + ' ' : '') + w.de;
      const u = new SpeechSynthesisUtterance(text); u.lang='de-DE'; u.rate=S.settings.speechRate;
      const v = getGermanVoice(); if(v) u.voice=v; speechSynthesis.speak(u);
    });
    trackAudioPlay();
  };
}
function vocabRowHTML(w){
  const bm = S.bookmarked[w.n] ? '★' : '☆';
  const speakText = (w.art && w.art !== '-' ? w.art + ' ' : '') + w.de;
  const m = getMastery('v'+w.n);
  return `<div class="vrow">
    <span class="vnum">#${w.n}</span>
    <div><div class="vde">${artHTML(w.art)}${esc(w.de)} <span class="mastery-chip mastery-${m.status}">${m.status}</span></div>
    <div style="font-size:11.5px;color:var(--muted);margin-top:2px"><span class="tag ${w.level}">${w.level}</span> <span style="margin-left:6px">${esc(w.topic)}</span></div></div>
    <div class="ven">
      <button class="speak-btn" data-speak="${esc(speakText)}">🔊</button>
      <span style="flex:1">${esc(meaningFull(w))}</span>
      <button class="bookmark ${S.bookmarked[w.n]?'on':''}" data-n="${w.n}">${bm}</button>
    </div>
  </div>`;
}

/* ============================================================
   ARTICLES
   ============================================================ */
let artState = {filter:'der', q:''};
function viewArticles(el){
  const nouns = VOCAB.filter(w => ['der','die','das'].includes(w.art));
  const counts = {der: nouns.filter(n => n.art === 'der').length, die: nouns.filter(n => n.art === 'die').length, das: nouns.filter(n => n.art === 'das').length};
  el.innerHTML = `<h2>📖 Articles</h2><p class="sub">${counts.der + counts.die + counts.das} nouns</p>
    <div class="stats" style="margin-bottom:14px">
      <div class="stat"><div class="n">${counts.der}</div><div class="l">der</div></div>
      <div class="stat"><div class="n">${counts.die}</div><div class="l">die</div></div>
      <div class="stat"><div class="n">${counts.das}</div><div class="l">das</div></div>
    </div>
    <div class="card"><div class="row">
      <button class="btn ${artState.filter==='der'?'':'ghost'}" data-art="der">der</button>
      <button class="btn ${artState.filter==='die'?'':'ghost'}" data-art="die">die</button>
      <button class="btn ${artState.filter==='das'?'':'ghost'}" data-art="das">das</button>
      <button class="btn small good" id="artPractice">⚡ Practice ∞</button>
    </div></div>
    <div class="art-browse" id="artList"></div>`;
  el.querySelectorAll('[data-art]').forEach(b => b.onclick = () => { artState.filter=b.dataset.art; viewArticles(el); });
  $('#artPractice').onclick = () => {
    quizState.mode = 'article'; quizState.count = 20; quizState.difficulty = 'normal';
    buildQuizQueue('article', 20, 'normal');
    location.hash = '#/quiz';
    setTimeout(() => renderQuiz(), 60);
  };
  const list = nouns.filter(n => n.art === artState.filter).slice(0, 200);
  const wrap = $('#artList');
  wrap.innerHTML = list.length ? list.map(n => `<div class="vrow" style="grid-template-columns:auto 1fr auto"><span class="art ${n.art}">${n.art}</span><div><div class="vde">${esc(n.de)}</div><div class="ven" style="text-align:left;justify-content:flex-start"><span>${esc(meaningFull(n))}</span></div></div><button class="speak-btn" data-speak="${esc(n.art+' '+n.de)}">🔊</button></div>`).join('') : `<div class="empty">${t('no_words')}</div>`;
  wireSpeakers(wrap);
}

/* ============================================================
   FLASHCARDS
   ============================================================ */
let flashState = {queue:[], idx:0, flipped:false};
function buildFlashQueue(){
  const due = dueWordKeys().map(k => VOCAB.find(w => 'v'+w.n === k)).filter(Boolean);
  flashState.queue = due.length ? shuffle(due) : shuffle(VOCAB).slice(0, 30);
  flashState.idx = 0; flashState.flipped = false;
}
function viewFlash(el){
  if(!flashState.queue.length) buildFlashQueue();
  el.innerHTML = `<h2>🧠 Flashcards</h2><p class="sub">SRS flashcards. Rate how well you knew it.</p>
    <div class="flash-wrap" id="flashWrap"></div>
    <div id="flashSrs" class="srs-buttons hidden">
      <button class="srs-btn again" data-q="0"><span class="srs-emoji">😵</span>Again</button>
      <button class="srs-btn hard" data-q="1"><span class="srs-emoji">😕</span>Hard</button>
      <button class="srs-btn good" data-q="2"><span class="srs-emoji">🙂</span>Good</button>
      <button class="srs-btn easy" data-q="3"><span class="srs-emoji">😎</span>Easy</button>
    </div>
    <div class="row mt" style="justify-content:center" id="flashRevealRow">
      <button class="btn ghost" id="fprev">← Prev</button>
      <button class="btn" id="freveal">Reveal</button>
      <button class="btn ghost" id="fnext">Next →</button>
    </div>
    <div class="center mt" style="color:var(--muted);font-size:13px" id="fcount"></div>`;
  $('#fprev').onclick = () => { if(flashState.idx > 0){ flashState.idx--; flashState.flipped = false; renderFlash(); } };
  $('#fnext').onclick = () => nextFlash();
  $('#freveal').onclick = () => { flashState.flipped = true; renderFlash(); };
  el.querySelectorAll('.srs-btn').forEach(b => b.onclick = () => {
    const w = flashState.queue[flashState.idx]; if(!w) return;
    updateMastery(vocabKey(w), +b.dataset.q);
    nextFlash();
  });
  renderFlash();
}
function renderFlash(){
  const wrap = $('#flashWrap'), total = flashState.queue.length;
  if(!total){ wrap.innerHTML = `<div class="empty">No cards.</div>`; return; }
  if(flashState.idx >= total) flashState.idx = 0;
  const w = flashState.queue[flashState.idx];
  const speakText = (w.art && w.art !== '-' ? w.art + ' ' : '') + w.de;
  const m = getMastery('v'+w.n);
  wrap.innerHTML = `<div class="flash ${flashState.flipped?'flipped':''}" id="flashCard">
    <div class="face front"><div class="big">${artHTML(w.art)}${esc(w.de)}</div><div class="small">Tap to reveal</div><div class="small" style="margin-top:12px">${esc(w.topic)} · ${w.level} · <span class="mastery-chip mastery-${m.status}">${m.status}</span></div></div>
    <div class="face back"><div class="big-en">${esc(meaningFull(w))}</div><div class="small">${artHTML(w.art)}${esc(w.de)}</div></div></div>
    <div class="center mt">${speakerBtn(speakText)}</div>`;
  $('#flashCard').onclick = e => { if(e.target.classList.contains('speak-btn'))return; flashState.flipped = !flashState.flipped; renderFlash(); };
  $('#fcount').textContent = `${flashState.idx+1} / ${total}`;
  wireSpeakers(wrap);
  if(flashState.flipped){ $('#flashSrs').classList.remove('hidden'); $('#flashRevealRow').classList.add('hidden'); }
  else { $('#flashSrs').classList.add('hidden'); $('#flashRevealRow').classList.remove('hidden'); }
  if(!flashState.flipped && S.settings.autoPlay) speakGerman(speakText);
}
function nextFlash(){ flashState.idx = (flashState.idx + 1) % flashState.queue.length; flashState.flipped = false; renderFlash(); }

/* ============================================================
   QUIZ — INFINITE
   ============================================================ */
let quizState = {mode:'article', queue:[], idx:0, score:0, answered:false, count:20, difficulty:'normal'};

const QUIZ_MODES = {
  article:     {label:'📖 Article', gen:(d) => generateVocabExercise('article', null, d)},
  de_en:       {label:'DE → EN', gen:(d) => generateVocabExercise('de-en', null, d)},
  en_de:       {label:'EN → DE', gen:(d) => generateVocabExercise('en-de', null, d)},
  opposite:    {label:'↔️ Opposites', gen:(d) => generateVocabExercise('opposite', null, d)},
  synonym:     {label:'📚 Synonyms', gen:(d) => generateVocabExercise('synonym', null, d)},
  listen:      {label:'🎧 Listening', gen:(d) => EXERCISE_REGISTRY.listening({level:'A2', difficulty:'normal'})},
  grammar:     {label:'📖 Grammar', gen:(d) => generateGrammarExerciseLadder('A2', 'normal')},
  connector:   {label:'🔗 Connectors', gen:(d) => generateConnectorExercise(rPick(CONNECTORS))},
  collocation: {label:'🧱 Collocations', gen:(d) => generateCollocationExercise(rPick(COLLOCATIONS))},
  compare:     {label:'⚖️ Compare', gen:(d) => generateComparisonExercise(rPick(VERB_COMPARISONS))},
  verbusage:   {label:'🔥 Verb usage', gen:(d) => generateVerbUsageExercise()},
  sentence:    {label:'🧩 Sentence', gen:(d) => EXERCISE_REGISTRY.sentence({level:'A2', difficulty:'normal'})},
  mixed:       {label:'🎲 Mixed', gen:(d) => EXERCISE_REGISTRY.mixed({level:'A2', difficulty:'normal'})}
};

function buildQuizQueue(mode, count, difficulty){
  const gen = (QUIZ_MODES[mode] || QUIZ_MODES.article).gen;
  const d = diffN(difficulty);
  quizState.queue = [];
  for(let i = 0; i < count; i++) quizState.queue.push(gen(d));
  quizState.idx = 0; quizState.score = 0; quizState.answered = false;
}

function viewQuiz(el){
  const modes = Object.keys(QUIZ_MODES);
  el.innerHTML = `<h2>${t('quiz_title')}</h2><p class="sub">${t('quiz_sub')}</p>
    <div class="card"><div class="row" style="gap:6px">
      ${modes.map(k => `<button class="btn small ${quizState.mode===k?'':'ghost'}" data-mode="${k}">${QUIZ_MODES[k].label}</button>`).join('')}
    </div></div>
    ${setupPanelHTML('quiz', quizState.count, quizState.difficulty)}
    <button class="btn" id="quizStart" style="width:100%">▶ Start (infinite)</button>
    <div id="quizBox" style="margin-top:14px"></div>`;
  el.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => { quizState.mode = b.dataset.mode; viewQuiz(el); });
  wireSetupPanel(el, (group, val) => {
    if(group === 'count') quizState.count = +val;
    if(group === 'difficulty') quizState.difficulty = val;
  });
  $('#quizStart').onclick = () => {
    const setup = readSetupPanel(el, 'quiz');
    quizState.count = setup.count;
    quizState.difficulty = setup.difficulty;
    buildQuizQueue(quizState.mode, setup.count, setup.difficulty);
    renderQuiz();
  };
}

function renderQuiz(){
  const box = $('#quizBox');
  if(!quizState.queue.length){ box.innerHTML = ''; return; }
  if(quizState.idx >= quizState.queue.length){
    // Refill — infinite
    const more = quizState.count || 20;
    const gen = (QUIZ_MODES[quizState.mode] || QUIZ_MODES.article).gen;
    const d = diffN(quizState.difficulty);
    for(let i = 0; i < more; i++) quizState.queue.push(gen(d));
  }
  const q = quizState.queue[quizState.idx];
  box.innerHTML = `<div class="card"><div class="qstat">
      <span>${t('question_of', quizState.idx + 1, quizState.queue.length)}</span>
      <span>${t('score_label', quizState.score)}</span>
    </div>
    <div style="font-size:16px;margin:8px 0 14px;line-height:1.5">${q.promptHTML}</div>
    <div id="opts">${q.options.map(o => `<button class="opt" data-v="${esc(o)}">${esc(o)}</button>`).join('')}</div>
    <div id="feedback" class="mt" style="font-size:13.5px;color:var(--muted)"></div>
    <button class="btn small ghost mt" id="quizStop">⏹ Stop</button>
  </div>`;
  box.querySelectorAll('.opt').forEach(b => b.onclick = () => answerQuiz(b, q));
  $('#quizStop').onclick = () => {
    quizState.queue = [];
    box.innerHTML = `<div class="card center"><h3>Stopped</h3><div class="mini-muted">You answered <b>${quizState.idx}</b> questions, ${quizState.score} correct.</div><button class="btn" id="again" style="margin-top:10px">New session</button></div>`;
    $('#again').onclick = () => viewQuiz($('#view'));
  };
  wireSpeakers(box);
}

function answerQuiz(btn, q){
  if(quizState.answered) return;
  quizState.answered = true;
  const ok = btn.dataset.v === q.correct;
  if(ok) quizState.score++;
  $$('#opts .opt').forEach(b => { b.disabled = true; if(b.dataset.v === q.correct) b.classList.add('correct'); else if(b === btn) b.classList.add('wrong'); });
  $('#feedback').innerHTML = ok ? '✅ Correct!' : `❌ Correct: <b>${esc(q.correct)}</b>. ${esc(q.explanation || '')}`;
  if(q.vocab) updateMastery(vocabKey(q.vocab), ok ? 2 : 0);
  if(!ok) recordMistake({type:q.skill || 'quiz', topic:q.topic || q.skill, prompt:q.prompt, userAnswer:btn.dataset.v, correctAnswer:q.correct, explanation:q.explanation, sourceId:q.sourceId});
  setTimeout(() => { quizState.idx++; quizState.answered = false; renderQuiz(); }, 1100);
}

/* ============================================================
   VERBS
   ============================================================ */
let verbTab = 'detail', verbDetailOpen = null;
function viewVerbs(el){
  el.innerHTML = `<h2>${t('verbs_title')}</h2><p class="sub">Conjugations, prefixes, usage, frequency.</p>
    <div class="card"><div class="row">
      <button class="btn ${verbTab==='detail'?'':'ghost'}" data-tab="detail">Detailed</button>
      <button class="btn ${verbTab==='usage'?'':'ghost'}" data-tab="usage">Usage & Frequency</button>
    </div></div><div id="verbBody"></div>`;
  el.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { verbTab = b.dataset.tab; verbDetailOpen = null; viewVerbs(el); });
  const body = $('#verbBody');
  if(verbTab === 'detail'){
    body.innerHTML = VERB_DETAILS.map((v,i) => `<div class="card" style="cursor:pointer" data-vidx="${i}">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap">
        <div><div style="font-weight:700;font-size:16px">${esc(v.infinitive)} <span class="tag ${v.level}">${v.level}</span></div>
        <div style="color:var(--muted);font-size:13px;margin-top:3px">${esc(v.meaning)}</div></div>
        ${speakerBtn(v.infinitive)}
      </div>
      ${VERB_USAGE[v.infinitive] ? `<div style="font-size:11.5px;color:var(--gold);margin-top:5px;font-weight:700">${VERB_USAGE[v.infinitive].band}</div>` : ''}
    </div>`).join('');
    body.querySelectorAll('[data-vidx]').forEach(c => c.onclick = e => { if(e.target.classList.contains('speak-btn'))return; verbDetailOpen = VERB_DETAILS[+c.dataset.vidx]; renderVerbDetail(body); });
    wireSpeakers(body);
  } else {
    const keys = Object.keys(VERB_USAGE);
    body.innerHTML = keys.map(k => {
      const u = VERB_USAGE[k];
      return `<div class="card"><div style="display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap">
        <div><div style="font-weight:750;font-size:18px">${esc(k)} ${speakerBtn(k, 16)}</div>
        <div style="color:var(--accent2);font-size:14px;font-weight:600;margin-top:2px">${esc(u.meaning)}</div></div>
        <div style="font-size:12px;color:var(--gold);font-weight:800">${u.band}</div>
      </div>
      <h4>Common contexts</h4><ul style="margin:6px 0 0 20px;padding:0;font-size:13.5px;line-height:1.7">${u.contexts.map(c => `<li>${esc(c)}</li>`).join('')}</ul>
      <h4>Patterns</h4><ul style="margin:6px 0 0 20px;padding:0;font-size:13.5px;line-height:1.7">${u.patterns.map(p => `<li>${esc(p)} ${speakerBtn(p, 11)}</li>`).join('')}</ul>
      ${u.alt && u.alt.length ? `<h4>Alternatives</h4><div class="row">${u.alt.map(a => `<span class="pill">${esc(a)}</span>`).join('')}</div>` : ''}
      <div class="cmp-note" style="margin-top:10px">💡 ${esc(u.note)}</div></div>`;
    }).join('');
    wireSpeakers(body);
  }
}
function renderVerbDetail(body){
  const v = verbDetailOpen; if(!v) return;
  const u = VERB_USAGE[v.infinitive];
  body.innerHTML = `<button class="btn small ghost" id="verbBack">← Back</button>
    <div class="card" style="margin-top:12px">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap">
        <div><div style="font-weight:750;font-size:20px">${esc(v.infinitive)} <span class="tag ${v.level}">${v.level}</span></div>
        <div style="color:var(--accent2);font-size:15px;font-weight:600;margin-top:4px">${esc(v.meaning)}</div></div>
        ${speakerBtn(v.infinitive, 18)}
      </div>
      ${u ? `<div style="font-size:12px;color:var(--gold);font-weight:800;margin-top:8px">${u.band}</div>` : ''}
      <h4>Präsens</h4>
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px;margin:6px 0">
        ${Object.entries(v.praesens).map(([pr,form]) => `<div style="background:var(--bg);border-radius:8px;padding:8px 10px;font-size:13px"><b>${pr}:</b> ${esc(form)}</div>`).join('')}
      </div>
      <h4>Präteritum & Perfekt</h4>
      <div class="mini-muted">Prät.: <b>${esc(v.praeteritum)}</b> · Perfekt: <b>${esc(v.perfekt)}</b> (aux: ${esc(v.auxiliary)})</div>
      <h4>Examples</h4>
      <ul style="list-style:none;padding:0;margin:6px 0">${v.examples.map(([de,en]) => `<li style="background:var(--bg);border-radius:7px;padding:8px 10px;margin-bottom:5px;display:flex;justify-content:space-between;gap:8px"><div><b>${esc(de)}</b><span style="display:block;font-size:12.5px;color:var(--muted)">${esc(en)}</span></div>${speakerBtn(de)}</li>`).join('')}</ul>
      ${u ? `<h4>Common contexts</h4><ul style="margin:6px 0 0 20px;padding:0;font-size:13.5px;line-height:1.7">${u.contexts.map(c => `<li>${esc(c)}</li>`).join('')}</ul>` : ''}
    </div>`;
  $('#verbBack').onclick = () => { verbDetailOpen = null; viewVerbs($('#view')); };
  wireSpeakers(body);
}

/* ============================================================
   PRONUNCIATION
   ============================================================ */
function viewPronounce(el){
  el.innerHTML = `<h2>${t('nav_pronounce').replace(/^[^ ]+ /,'')}</h2><p class="sub">${PRONUNCIATION_RULES.length} rules.</p>
    <div class="card"><button class="btn small" id="testVoice">🔊 Test voice</button></div>
    <div>${PRONUNCIATION_RULES.map(r => `<div class="card"><div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:6px">
      <span style="font-size:22px;font-weight:800;color:var(--accent);background:var(--bg);padding:4px 12px;border-radius:8px">${esc(r.letter)}</span>
      <span style="font-size:14px;font-weight:700;color:var(--accent2)">${esc(r.sound)}</span></div>
      <div class="mini-muted">${esc(r.context)}</div>
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:6px;margin-top:8px">${r.examples.map(([de,en]) => `<div style="background:var(--bg);border-radius:7px;padding:7px 10px;font-size:13px;display:flex;align-items:center;gap:6px"><b style="flex:1">${esc(de)}</b><span class="mini-muted">${esc(en)}</span>${speakerBtn(de, 11)}</div>`).join('')}</div>
      <div class="mini-muted" style="margin-top:8px;font-style:italic">💡 ${esc(r.note)}</div>
    </div>`).join('')}</div>`;
  $('#testVoice').onclick = () => speakGerman('Guten Tag. Ich heiße Anna. Wie geht es dir?');
  wireSpeakers(el);
}

/* ============================================================
   SYNONYMS / PATTERNS
   ============================================================ */
let synState = {tab:'opposites'};
function viewSynonyms(el){
  el.innerHTML = `<h2>↔️ Opposites & Synonyms</h2>
    <div class="row" style="margin-bottom:12px">
      <button class="btn ${synState.tab==='opposites'?'':'ghost'}" data-tab="opposites">↔️ Gegenteil (${OPPOSITES.length})</button>
      <button class="btn ${synState.tab==='synonyms'?'':'ghost'}" data-tab="synonyms">📚 Synonyme (${SYNONYMS.length})</button>
    </div>
    <div id="synList"></div>`;
  el.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { synState.tab = b.dataset.tab; viewSynonyms(el); });
  const wrap = $('#synList');
  if(synState.tab === 'opposites'){
    wrap.innerHTML = OPPOSITES.map(([d1,e1,d2,e2]) => `<div style="background:var(--card);border:1px solid var(--line);border-radius:11px;padding:10px 12px;margin-bottom:6px;display:grid;grid-template-columns:1fr auto 1fr;gap:10px;align-items:center">
      <div style="display:flex;align-items:center;gap:6px"><button class="speak-btn" data-speak="${esc(d1)}">🔊</button><span style="font-weight:650">${esc(d1)}<span style="display:block;font-size:11.5px;color:var(--muted);font-weight:400">${esc(e1)}</span></span></div>
      <div style="color:var(--accent);font-weight:800">↔</div>
      <div style="display:flex;align-items:center;gap:6px;justify-content:flex-end;text-align:right"><span style="font-weight:650">${esc(d2)}<span style="display:block;font-size:11.5px;color:var(--muted);font-weight:400">${esc(e2)}</span></span><button class="speak-btn" data-speak="${esc(d2)}">🔊</button></div>
    </div>`).join('');
  } else {
    wrap.innerHTML = SYNONYMS.map(s => `<div style="background:var(--card);border:1px solid var(--line);border-radius:11px;padding:10px 12px;margin-bottom:6px">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;flex-wrap:wrap">
        <button class="speak-btn" data-speak="${esc(s.word)}">🔊</button>
        <b>${esc(s.word)}</b><span class="mini-muted">${esc(s.en)}</span>
      </div>
      <div style="display:flex;flex-wrap:wrap;gap:6px">${s.syn.map(([de,en]) => `<span class="pill"><button class="speak-btn" data-speak="${esc(de)}" style="min-width:20px;min-height:20px;padding:1px;font-size:10px;margin-right:4px">🔊</button>${esc(de)}<span class="mini-muted" style="font-size:11px"> · ${esc(en)}</span></span>`).join('')}</div>
    </div>`).join('');
  }
  wireSpeakers(wrap);
}
function viewPatterns(el){
  el.innerHTML = `<h2>${t('patterns_title')}</h2><p class="sub">${PATTERNS.length} frames.</p>
    ${PATTERNS.map(p => `<div class="card"><div style="font-size:11px;font-weight:800;color:var(--accent)">#${p[0]}</div>
      <div style="font-weight:750;font-size:15.5px;margin:4px 0 6px">${esc(p[1])}</div>
      <div class="mini-muted" style="font-size:12.5px;margin-bottom:7px">${esc(p[2])}</div>
      <div style="background:var(--bg);border-left:3px solid var(--accent2);border-radius:6px;padding:8px 12px;font-style:italic;font-size:13.5px;display:flex;justify-content:space-between;gap:8px;align-items:flex-start">
        <div style="flex:1">${esc(p[3])}<b style="display:block;font-style:normal;color:var(--muted);font-size:12px;margin-top:4px">${esc(p[4])}</b></div>
        ${speakerBtn(p[3])}
      </div>
    </div>`).join('')}`;
  wireSpeakers(el);
}

/* ============================================================
   GRAMMAR — INFINITE PRACTICE
   ============================================================ */
