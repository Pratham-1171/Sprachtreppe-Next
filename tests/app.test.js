const test = require('node:test'), assert = require('node:assert');
const {load, closeAll} = require('./harness'), {build} = require('./build-helper');
test.after(closeAll);
const wait = ms => new Promise(r => setTimeout(r, ms));
const real = errs => errs.filter(e => !/scrollTo|Not implemented/.test(e));
const go = async (w, v) => { w.location.hash = '#/' + v; w.dispatchEvent(new w.HashChangeEvent('hashchange')); await wait(40); };

test('local build: every screen renders without a script error', async () => {
  const {window: w, errors} = load(build({ALLOW_LOCAL_MODE: '1'})); await wait(600);
  assert.deepEqual(real(errors), []);
  const views = ['home','session','review','vocab','grammar','quiz','flash','verbs','connectors','collocations','compare','mistakes','sentence','spelling','dictation','families','articles','pronounce','synonyms','patterns','listen','speak','read','write','exam','resources','progress','settings'];
  for (const v of views) { errors.length = 0; await go(w, v); assert.deepEqual(real(errors), [], 'view ' + v); }
  await go(w, 'synonyms');
  const oppositePair = w.document.querySelector('#synList > div');
  assert.ok(oppositePair, 'opposites list renders a row');
  assert.match(oppositePair.getAttribute('style') || '', /grid-template-columns:minmax\\(0,1fr\\) auto minmax\\(0,1fr\\)/, 'opposite columns can shrink below min-content width');
  assert.match(oppositePair.children[0].getAttribute('style') || '', /min-width:0/, 'left word column can shrink');
  assert.match(oppositePair.children[0].querySelector('span').getAttribute('style') || '', /overflow-wrap:anywhere/, 'long left words can wrap on narrow screens');
  assert.match(oppositePair.children[2].getAttribute('style') || '', /min-width:0/, 'right word column can shrink');
  assert.match(oppositePair.children[2].querySelector('span').getAttribute('style') || '', /overflow-wrap:anywhere/, 'long right words can wrap on narrow screens');
  assert.equal(w.__SP_ENGINE_VERSION, '8.0-grammar-core');
  assert.equal(w.SP_AUTH.enabled, false, 'local mode has no login');
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
