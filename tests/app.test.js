const test = require('node:test'), assert = require('node:assert');
const fs = require('node:fs');
const {load, closeAll} = require('./harness'), {build} = require('./build-helper');
test.after(closeAll);
const wait = ms => new Promise(r => setTimeout(r, ms));
const real = errs => errs.filter(e => !/scrollTo|Not implemented/.test(e));
const go = async (w, v) => { w.location.hash = '#/' + v; w.dispatchEvent(new w.HashChangeEvent('hashchange')); await wait(40); };

test('local build: every screen renders without a script error', async () => {
  const {window: w, errors} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  assert.deepEqual(real(errors), []);
  const views = ['home','learn','course','practice','dashboard','assignments','session','review','vocab','grammar','quiz','flash','verbs','connectors','collocations','compare','mistakes','sentence','spelling','dictation','families','articles','pronounce','synonyms','patterns','listen','speak','read','write','exam','resources','progress','settings'];
  for (const v of views) { errors.length = 0; await go(w, v); assert.deepEqual(real(errors), [], 'view ' + v); }
  assert.equal(w.__SP_ENGINE_VERSION, '8.0-grammar-core');
  assert.equal(w.SP_AUTH.enabled, false, 'local mode has no login');
});
test('web build bundles shared staff logic and responsive app styling', async () => {
  const file = build({ALLOW_LOCAL_MODE: '1'});
  const html = fs.readFileSync(file, 'utf8');
  for (const marker of [
    'id="spWebFirst"',
    'id="spLmsMobileFix"',
    'content="#315f52"',
    'window.viewAssignments=renderAssignments;',
    'window.viewFlutterLearn=viewFlutterLearn;',
    'window.viewFlutterPractice=viewFlutterPractice;',
    "s.id = 'spFlutterParity';",
    'window.viewTeachers=renderTeachers;',
    'classroom:(window.viewClassroom||viewHome)',
    'html,body{max-width:100%;overflow-x:hidden}'
  ]) assert.ok(html.includes(marker), 'built web app is missing ' + marker);
  assert.ok(!html.includes('--bg:#f4f7ff'), 'LMS must not override the app background theme');
  assert.ok(!html.includes('--accent:#6d28d9'), 'LMS must not override the app accent theme');
  const manifest = JSON.parse(fs.readFileSync(file.replace('index.html', 'manifest.webmanifest'), 'utf8'));
  assert.equal(manifest.theme_color, '#315f52');
  assert.equal(manifest.background_color, '#ffffff');
  const {window: w, errors} = load(file);
  await wait(600);
  assert.deepEqual(real(errors), []);
  assert.equal(w.SP_AUTH.enabled, false, 'local mode keeps account sync disabled');
});

test('built web app ships the forest/lime palette and bypasses stale HTML caches', () => {
  const file = build({ALLOW_LOCAL_MODE: '1'});
  const fs = require('node:fs');
  const html = fs.readFileSync(file, 'utf8');
  for (const marker of [
    '.logo span{color:var(--accent2)}',
    'nav button.active{background:color-mix(in oklch,var(--accent2) 24%,var(--card))',
    '.today-dash{background:linear-gradient(125deg',
    '.tag.A2{background:color-mix(in oklch,var(--accent2) 34%,var(--card))',
    '.mastery-MASTERED{background:color-mix(in oklch,var(--accent2) 48%,var(--card))',
    '.logo span{font-size:12px;color:var(--accent2);font-weight:700}',
    'nav button.active{background:color-mix(in oklch,var(--accent2) 24%,var(--card));color:var(--text);border:0}',
    'nav button.active{background:color-mix(in oklch,var(--accent2) 18%,var(--card));color:var(--text);border-bottom:3px solid var(--accent2);border-radius:0}',
  ]) assert.ok(html.includes(marker), 'app theme is missing ' + marker);
  const sw = fs.readFileSync(file.replace('index.html', 'sw.js'), 'utf8');
  assert.ok(sw.includes("new Request(file, { cache: 'reload' })"), 'service worker install must fetch latest HTML');
  assert.ok(sw.includes("new Request(e.request, { cache: 'no-store' })"), 'HTML navigation must bypass stale browser cache');
});

test('the app is English-only and has no Gujarati language UI or translation dictionary', () => {
  const file = build({ALLOW_LOCAL_MODE: '1'});
  const fs = require('node:fs');
  const html = fs.readFileSync(file, 'utf8');
  assert.ok(!/[\u0A80-\u0AFF]/.test(html), 'built app must not contain Gujarati script');
  for (const marker of ['langBtn', 's-lang', 'UI.gu', 'guOf(', 'GUJARATI DICTIONARY', 'Gujarati', 'english-gujarati', 'Noto Sans Gujarati']) {
    assert.ok(!html.includes(marker), 'English-only build still contains ' + marker);
  }
  const {window: w, errors} = load(file);
  assert.equal(w.document.documentElement.lang, 'en');
  assert.deepEqual(real(errors), []);
});

test('reading screen is interactive and scores answers', async () => {
  const {window: w, errors} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  await go(w, 'read'); const opts = [...w.document.querySelectorAll('.rd-opts .opt')]; assert.equal(opts.length, 20);
  w.document.querySelectorAll('[data-id]').forEach(box => { const q = box.dataset.id; const correct = w.eval('readState.current').items.concat(w.eval('readState.current').tfs.map((t, i) => Object.assign({id: 't' + i}, t))); });
  const r = w.eval('readState.current'); const all = r.items.map((i, k) => Object.assign({id: 'q' + k}, i)).concat(r.tfs.map((i, k) => Object.assign({id: 't' + k}, i)));
  all.forEach(q => { const box = w.document.querySelector(`[data-id="${q.id}"]`); [...box.querySelectorAll('.opt')].find(b => b.dataset.v === q.correct).click(); });
  assert.match(w.document.querySelector('#rdScore').textContent, new RegExp(`Score: ${all.length} / ${all.length}`));
  assert.deepEqual(real(errors), []);
});
test('writing screen gives live checklist + feedback and records the attempt', async () => {
  const {window: w, errors} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  await go(w, 'write'); const pad = w.document.querySelector('#wPad');
  pad.value = w.eval('writeState.current.model'); pad.dispatchEvent(new w.Event('input'));
  assert.ok([...w.document.querySelectorAll('.wr-mark')].every(m => m.textContent === '☑'));
  w.document.querySelector('#wCheck').click();
  assert.match(w.document.querySelector('#wFb').textContent, /Score 100\/100/);
  assert.equal(w.eval('S.writingLog.length'), 1); assert.deepEqual(real(errors), []);
});
test('generated exercises through the app registry: valid, adaptive stats recorded in a session', async () => {
  const {window: w} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  const r = JSON.parse(w.eval(`(function(){let bad=0;const sk=['mixed','gen','sentence','grammar','vocab','article','de_en','en_de','opposite','synonym','listening','connector','collocation','compare','verbusage'];
    for(let i=0;i<4500;i++){const ex=generateExercise({skill:sk[i%sk.length],level:['A1','A2','B1'][i%3],difficulty:'mixed'});if(!ex||!ex.options||!ex.options.includes(ex.correct)||new Set(ex.options).size!==ex.options.length)bad++}return JSON.stringify({bad})})()`));
  assert.equal(r.bad, 0);
});
test("my noun genders agree with the course's own vocabulary list", async () => {
  const {window: w} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  const mism = JSON.parse(w.eval(`(function(){const out=[];const map={};VOCAB.forEach(v=>{if(['der','die','das'].includes(v.art))(map[v.de]=map[v.de]||new Set()).add(v.art)});
    DE.NOUNS.forEach(n=>{const s=map[n.de];if(s&&!s.has(n.art))out.push(n.de+': lexicon '+n.art+' vs vocab '+[...s].join('/'))});return JSON.stringify({out,checked:DE.NOUNS.filter(n=>map[n.de]).length})})()`));
  assert.deepEqual(mism.out, []); assert.ok(mism.checked > 60, 'cross-checked ' + mism.checked + ' nouns');
});
test('sentence builder accepts every valid word order and ignores capitalisation', async () => {
  const {window: w, errors} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  let tested = 0;
  for (let k = 0; k < 40 && tested < 6; k++) {
    w.eval('sbState.item=null;sbState.used=[];sbState.answer=[]'); await go(w, 'sentence');
    const item = w.eval('sbState.item'); if (!item.accept.length) continue;
    for (const variant of [item.answer].concat(item.accept)) {
      w.eval('sbState.used=sbState.item.tokens.map(()=>false);sbState.answer=[]'); await go(w, 'sentence');
      const words = variant.replace(/\.$/, '').split(' ');
      words.forEach(word => { const tile = [...w.document.querySelectorAll('#sbTiles button, .tile, [data-tile]')].find(b => !b.disabled && b.textContent.trim().toLowerCase() === word.toLowerCase()); if (tile) tile.click(); });
      w.document.querySelector('#sbCheck').click();
      assert.match(w.document.querySelector('#sbFb').textContent, /Correct!/, 'variant accepted: ' + variant);
    }
    tested++;
  }
  assert.ok(tested >= 1, 'found items with alternatives'); assert.deepEqual(real(errors), []);
});
