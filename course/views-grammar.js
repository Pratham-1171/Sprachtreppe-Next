/* Source module: views-grammar.js
 * Detailed CEFR grammar cards and interactive checks.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
function viewGrammar(el){
  let activeLevel = 'all';
  const render = () => {
    const sections = activeLevel === 'all' ? GRAMMAR_DATA : GRAMMAR_DATA.filter(g => g.level === activeLevel);
    el.innerHTML = `<h2>${t('grammar_title')}</h2><p class="sub">Rules, examples, mistakes, exercises.</p>
      <div class="card"><div class="row">
        <button class="btn ${activeLevel==='all'?'':'ghost'}" data-lvl="all">All</button>
        <button class="btn ${activeLevel==='A1'?'':'ghost'}" data-lvl="A1">A1</button>
        <button class="btn ${activeLevel==='A2'?'':'ghost'}" data-lvl="A2">A2</button>
        <button class="btn ${activeLevel==='B1'?'':'ghost'}" data-lvl="B1">B1</button>
        <button class="btn ${activeLevel==='B2'?'':'ghost'}" data-lvl="B2">B2</button>
        <button class="btn ${activeLevel==='C1'?'':'ghost'}" data-lvl="C1">C1</button>
        <button class="btn ${activeLevel==='C2'?'':'ghost'}" data-lvl="C2">C2</button>
        <button class="btn small good" id="grammarPractice">⚡ Practice ∞</button>
      </div></div>
      ${sections.map(sec => { const offset = GRAMMAR_DATA.slice(0, GRAMMAR_DATA.indexOf(sec)).filter(g => g.level === sec.level).reduce((sum, g) => sum + g.items.length, 0); return `<h3>${esc(sec.level)} · ${esc(sec.title)}</h3>${sec.items.map((it,idx) => grammarCardHTML(sec.level, offset + idx, it)).join('')}`; }).join('')}`;
    el.querySelectorAll('[data-lvl]').forEach(b => b.onclick = () => { activeLevel = b.dataset.lvl; render(); });
    el.querySelectorAll('.g-exercise').forEach(ex => {
      const correct = +ex.dataset.correct;
      ex.querySelectorAll('.opt').forEach(b => b.onclick = () => {
        if(ex.dataset.done) return; ex.dataset.done = '1';
        const ok = +b.dataset.i === correct;
        ex.querySelectorAll('.opt').forEach(x => { x.disabled = true; if(+x.dataset.i === correct) x.classList.add('correct'); else if(x === b) x.classList.add('wrong'); });
        const fb = ex.querySelector('.fb');
        fb.textContent = (ok ? '✅ ' : '❌ Correct: ') + ex.dataset.why;
        fb.style.background = ok ? 'rgba(22,163,74,.12)' : 'rgba(225,29,72,.10)';
        S.grammarDone[ex.dataset.key] = 1; STORE.save();
        if(!ok) recordMistake({type:'grammar', topic:ex.dataset.key, prompt:ex.querySelector('.q').textContent, userAnswer:ex.querySelectorAll('.opt')[+b.dataset.i].textContent, correctAnswer:ex.querySelectorAll('.opt')[correct].textContent, explanation:ex.dataset.why, sourceId:ex.dataset.key});
      });
    });
    wireSpeakers(el);
    const gp = $('#grammarPractice');
    if(gp) gp.onclick = () => {
      quizState.mode = 'grammar'; quizState.level = activeLevel === 'all' ? 'A1' : activeLevel; quizState.count = 20; quizState.difficulty = 'normal';
      buildQuizQueue('grammar', 20, 'normal');
      location.hash = '#/quiz';
      setTimeout(() => renderQuiz(), 60);
    };
  };
  render();
}
function grammarCardHTML(level, idx, it){
  const key = level + '_' + idx;
  const guide = (typeof GRAMMAR_GUIDE !== 'undefined' && GRAMMAR_GUIDE[level + '|' + it.title]) || null;
  const done = S.grammarDone[key] ? `<span class="tag" style="background:rgba(22,163,74,.15);color:var(--ok);margin-left:8px">DONE</span>` : '';
  const note = (label, text) => text ? `<div class="grammar-note"><b>` + esc(label) + `</b><div>` + esc(text) + `</div></div>` : '';
  const steps = guide && Array.isArray(guide.steps) && guide.steps.length
    ? `<div class="grammar-note"><b>Build it step by step</b><ol>` + guide.steps.map(s => `<li>` + esc(s) + `</li>`).join('') + `</ol></div>` : '';
  const extraExamples = guide && Array.isArray(guide.extraExamples) && guide.extraExamples.length
    ? `<div class="grammar-note"><b>More examples</b>` + guide.extraExamples.map(([de,en]) => `<div class="grammar-example"><span>` + esc(de) + `</span><span>` + esc(en) + `</span></div>`).join('') + `</div>` : '';
  return `<div class="card grammar-card">
    <div style="font-weight:750;font-size:16px">` + esc(it.title) + done + `</div>
    <div class="grammar-explanation">` + esc(it.explanation) + `</div>
    ` + note('When to use it', guide && guide.when) + steps + `
    <div class="grammar-rule-label">RULE / SENTENCE PATTERN</div>
    <div class="grammar-rule">` + esc(it.rule) + `</div>
    ` + note('Remember', guide && guide.tip) + note('Important contrast', guide && guide.contrast) + extraExamples + `
    <div class="grammar-rule-label">EXAMPLES</div>
    <div class="grammar-examples">` + it.examples.map(([de,en]) => `<div class="grammar-example"><span class="grammar-de">` + esc(de) + speakerBtn(de, 11) + `</span><span class="grammar-en">` + esc(en) + `</span></div>`).join('') + `</div>
    <div class="grammar-mistake-label">COMMON MISTAKES</div>
    <div class="grammar-mistakes">` + it.mistakes.map(([bad,good]) => `<div class="grammar-mistake"><span>` + esc(bad) + `</span><span>` + esc(good) + `</span></div>`).join('') + `</div>
    <div class="g-exercise grammar-exercise" data-correct="` + it.exercise.correct + `" data-key="` + esc(key) + `" data-why="` + esc(it.exercise.why) + `">
      <div class="grammar-question">✏️ ` + esc(it.exercise.q) + `</div>
      ` + it.exercise.options.map((o,i) => `<button class="opt" data-i="` + i + `">` + esc(o) + `</button>`).join('') + `
      <div class="fb grammar-feedback"></div>
    </div>
  </div>`;
}


/* ============================================================
   LISTENING — INFINITE
   ============================================================ */
let listenState = {current: null};
