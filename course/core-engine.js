/* Source module: core-engine.js
 * Speech, local state, mastery, and exercise-generation helpers.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
let _voice = null;
function getGermanVoice(){
  if(_voice) return _voice;
  if(!('speechSynthesis' in window)) return null;
  const voices = speechSynthesis.getVoices();
  _voice = voices.find(v => v.lang === 'de-DE') || voices.find(v => v.lang && v.lang.startsWith('de')) || null;
  return _voice;
}
if('speechSynthesis' in window) speechSynthesis.onvoiceschanged = () => { _voice = null; getGermanVoice(); };
function speakGerman(text, rate){
  if(!S.settings.audioEnabled) return;
  if(!('speechSynthesis' in window)) return;
  speechSynthesis.cancel();
  const clean = String(text).replace(/\s+/g, ' ').trim();
  const u = new SpeechSynthesisUtterance(clean);
  u.lang = 'de-DE'; u.rate = rate || S.settings.speechRate || 0.9; u.pitch = 1;
  const v = getGermanVoice(); if(v) u.voice = v;
  speechSynthesis.speak(u);
  trackAudioPlay();
}
function speakerBtn(text, size){
  const sz = size ? `style="font-size:${size};min-width:28px;min-height:28px;padding:4px"` : '';
  return `<button class="speak-btn" data-speak="${esc(text)}" aria-label="Pronounce" ${sz}>🔊</button>`;
}
function wireSpeakers(root){
  (root || document).querySelectorAll('.speak-btn[data-speak]').forEach(b => {
    if(b.dataset.wired) return; b.dataset.wired = '1';
    b.addEventListener('click', e => {
      e.stopPropagation();
      speakGerman(b.dataset.speak);
      b.style.transform = 'scale(0.85)';
      setTimeout(() => b.style.transform = '', 180);
    });
  });
}

/* ============================================================
   STATE
   ============================================================ */
const STORE = {
  key:'de-a1b1-v5',
  legacyKey:'de-a1b1-v4',
  defaults(){
    return {
      known:{}, bookmarked:{}, quizStats:{}, lastView:'home',
      grammarDone:{}, listeningDone:{}, speakingDone:{}, writingDone:{},
      mastery:{}, mistakes:{},
      streak:{current:0, longest:0, lastStudyDate:null},
      studyTime:{today:0, total:0, day:null, sessions:0, week:0, weekStart:null},
      achievements:{}, sessionHistory:[],
      mistakesCleared:0, familiesViewed:0, audioPlays:0, sentencesBuilt:0, spelledCorrect:0,
      connectorsDone:0, collocationsDone:0, readingsGenerated:0, listeningsDone:0, writingsDone:0,
      settings:{
        lang:'en', theme:'light',
        fontSize:'normal', compactNav:false, reduceMotion:false, rememberLast:true,
        audioEnabled:true, autoPlay:false, speechRate:0.9,
        defaultCount:10, defaultDifficulty:'mixed',
        showExplanation:true, strictSpelling:true,
        dailyGoal:20, newWordsPerDay:10, sessionLen:15
      }
    };
  },
  load(){
    const d = this.defaults();
    try{
      const old = localStorage.getItem(this.legacyKey);
      if(old){ try{ const o = JSON.parse(old); Object.assign(d, o); }catch(e){} }
      const cur = localStorage.getItem(this.key);
      if(cur){
        try{ const c = JSON.parse(cur); Object.assign(d, c); if(c.settings) d.settings = Object.assign(this.defaults().settings, c.settings); }catch(e){}
      }
    }catch(e){}
    return d;
  },
  save(){ try{ localStorage.setItem(this.key, JSON.stringify(S)); }catch(e){} }
};
const S = STORE.load();
const $  = (sel, root=document) => root.querySelector(sel);
const $$ = (sel, root=document) => Array.from(root.querySelectorAll(sel));
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const shuffle = a => { const x=a.slice(); for(let i=x.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[x[i],x[j]]=[x[j],x[i]];} return x; };
const pct = (a,b) => b ? Math.round(100*a/b) : 0;
function artHTML(art){ if(!art||art==='-') return ''; return `<span class="art ${art}">${art}</span>`; }

/* ============================================================
   LEARNING ENGINE
   ============================================================ */
function vocabKey(w){ return 'v' + w.n; }
function getMastery(key){
  return S.mastery[key] || {seen:0, correct:0, wrong:0, streak:0, ease:2.5, interval:0, lastSeen:0, nextReview:0, status:'NEW'};
}
function updateMastery(key, quality){
  let q = quality;
  if(q === true) q = 2;
  if(q === false) q = 0;
  const m = getMastery(key);
  m.seen++;
  if(q >= 1){ m.correct++; m.streak++; } else { m.wrong++; m.streak = 0; }
  if(q === 0){ m.interval = 10/(60*24); m.ease = Math.max(1.3, m.ease - 0.2); }
  else if(q === 1){ m.interval = m.interval ? Math.max(1, m.interval * 1.2) : 1; m.ease = Math.max(1.3, m.ease - 0.15); }
  else if(q === 2){ m.interval = m.interval ? Math.max(1, m.interval * m.ease) : 1; }
  else { m.interval = m.interval ? Math.max(3, m.interval * m.ease * 1.3) : 3; m.ease = Math.min(3.0, m.ease + 0.15); }
  m.interval = Math.min(m.interval, 365);
  m.lastSeen = Date.now();
  m.nextReview = Date.now() + m.interval * 24*60*60*1000;
  if(m.correct >= 8 && m.streak >= 4) m.status = 'MASTERED';
  else if(m.correct >= 4 && m.streak >= 2) m.status = 'STRONG';
  else if(m.correct >= 2) m.status = 'FAMILIAR';
  else if(m.seen > 0) m.status = 'LEARNING';
  S.mastery[key] = m;
  if(m.status === 'MASTERED' || m.status === 'STRONG') S.known[key] = 1;
  STORE.save(); checkAchievements();
  return m;
}
function dueWordKeys(){ const now = Date.now(); return Object.keys(S.mastery).filter(k => k.startsWith('v') && S.mastery[k].nextReview <= now); }
function dueCount(){ return dueWordKeys().length; }
function recordMistake({type, topic, prompt, userAnswer, correctAnswer, explanation, sourceId}){
  const key = type + '::' + (sourceId || prompt);
  if(!S.mistakes[key]){
    S.mistakes[key] = {type, topic, prompt, userAnswer, correctAnswer, explanation, count:0, lastSeen:0, sourceId};
  }
  const m = S.mistakes[key];
  m.count++; m.userAnswer = userAnswer; m.correctAnswer = correctAnswer; m.lastSeen = Date.now();
  STORE.save();
  return m;
}
function clearMistake(key){ delete S.mistakes[key]; S.mistakesCleared = (S.mistakesCleared||0) + 1; STORE.save(); checkAchievements(); }
function clearAllMistakes(){ S.mistakes = {}; STORE.save(); }
function touchStreak(){
  const today = new Date().toISOString().slice(0,10);
  if(S.streak.lastStudyDate === today) return;
  const y = new Date(Date.now() - 86400000).toISOString().slice(0,10);
  if(S.streak.lastStudyDate === y) S.streak.current++; else S.streak.current = 1;
  S.streak.lastStudyDate = today;
  if(S.streak.current > S.streak.longest) S.streak.longest = S.streak.current;
  STORE.save(); checkAchievements();
}
function addStudyTime(seconds){
  const today = new Date().toISOString().slice(0,10);
  const weekStart = getWeekStart();
  if(!S.studyTime.day || S.studyTime.day !== today){ S.studyTime.day = today; S.studyTime.today = 0; }
  if(!S.studyTime.weekStart || S.studyTime.weekStart !== weekStart){ S.studyTime.weekStart = weekStart; S.studyTime.week = 0; }
  S.studyTime.today += seconds; S.studyTime.week += seconds; S.studyTime.total += seconds;
  STORE.save();
}
function getWeekStart(){
  const d = new Date(); const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.setDate(diff)).toISOString().slice(0,10);
}
function trackAudioPlay(){ S.audioPlays = (S.audioPlays||0) + 1; STORE.save(); checkAchievements(); }
function checkAchievements(){
  let changed = false;
  ACHIEVEMENTS.forEach(a => {
    if(!S.achievements[a.id]){
      try{ if(a.check(S)){ S.achievements[a.id] = Date.now(); changed = true; } }catch(e){}
    }
  });
  if(changed) STORE.save();
}

/* ============================================================
   FINGERPRINT DEDUP
   ============================================================ */
const __recentFingerprints = [];
const MAX_FINGERPRINTS = 200;
function exerciseFingerprint(text){
  return String(text).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"")
    .replace(/[^\p{L}\p{N}\s]/gu,"").replace(/\s+/g," ").trim();
}
function isDuplicate(fp){ return __recentFingerprints.includes(fp); }
function rememberFingerprint(fp){
  __recentFingerprints.push(fp);
  if(__recentFingerprints.length > MAX_FINGERPRINTS) __recentFingerprints.shift();
}
function pick(arr){ return arr[Math.floor(Math.random()*arr.length)]; }

/* ============================================================
   VOCAB EXERCISE GENERATOR
   ============================================================ */
function distractorCount(difficulty){ return difficulty <= 1 ? 2 : 3; }
function betterDistractors(w, count, mode){
  // Prefer same level, same topic, same article (for nouns), similar length; avoid identical meanings
  const sameLevel = VOCAB.filter(x => x !== w && x.level === w.level);
  const sameTopic = sameLevel.filter(x => x.topic === w.topic);
  const sameArt = VOCAB.filter(x => x !== w && x.art && x.art === w.art && x.art !== '-');
  let pool = [];
  if(mode === 'meaning'){
    const correct = meaningFull(w);
    const prefer = (sameTopic.length >= count ? sameTopic : sameLevel.length >= count ? sameLevel : VOCAB)
      .filter(x => meaningFull(x) !== correct);
    pool = prefer;
  } else if(mode === 'de'){
    const prefer = (sameTopic.length >= count ? sameTopic : sameLevel.length >= count ? sameLevel : VOCAB)
      .filter(x => x.de !== w.de);
    // Prefer similar length words for harder confusion
    prefer.sort((a,b) => Math.abs(a.de.length - w.de.length) - Math.abs(b.de.length - w.de.length));
    pool = prefer;
  } else {
    pool = VOCAB.filter(x => x !== w);
  }
  return shuffle(pool).slice(0, count);
}
function generateVocabExercise(type, pool, difficulty, level){
  difficulty = difficulty || 2;
  const basePool = pool && pool.length ? pool : VOCAB.filter(w => !level || w.level === level);
  const usePool = basePool.length ? basePool : VOCAB;
  let attempts = 0;
  while(attempts < 20){
    const w = usePool[Math.floor(Math.random() * usePool.length)];
    const speakText = (w.art && w.art !== '-' ? w.art + ' ' : '') + w.de;
    const type_ = type || pick(['de-en','en-de','article','listen']);
    let ex;
    if(type_ === 'de-en'){
      const correct = meaningFull(w);
      const wrongPool = betterDistractors(w, distractorCount(difficulty), 'meaning');
      const options = shuffle([correct, ...wrongPool.map(x => meaningFull(x))]);
      // Deduplicate options just in case
      const unique = [...new Set(options)];
      while(unique.length < distractorCount(difficulty)+1){
        const extra = meaningFull(VOCAB[Math.floor(Math.random()*VOCAB.length)]);
        if(!unique.includes(extra)) unique.push(extra);
      }
      ex = {skill:'vocabulary', prompt:`What does "${speakText}" mean?`, promptHTML:`What does <b>${esc(speakText)}</b> mean? ${speakerBtn(speakText)}`,
        options: unique.slice(0, distractorCount(difficulty)+1), correct, explanation:`${speakText} = ${meaningFull(w)}`, sourceId:'v'+w.n, difficulty, vocab:w};
    } else if(type_ === 'en-de'){
      const correct = w.de;
      const wrongPool = betterDistractors(w, distractorCount(difficulty), 'de');
      const options = shuffle([correct, ...wrongPool.map(x => x.de)]);
      const unique = [...new Set(options)];
      while(unique.length < distractorCount(difficulty)+1){
        const extra = VOCAB[Math.floor(Math.random()*VOCAB.length)].de;
        if(!unique.includes(extra)) unique.push(extra);
      }
      ex = {skill:'vocabulary', prompt:`How do you say "${w.en}" in German?`, promptHTML:`How do you say <b>${esc(meaningFull(w))}</b> in German?`,
        options: unique.slice(0, distractorCount(difficulty)+1), correct, explanation:`"${w.en}" = ${speakText}`, sourceId:'v'+w.n, difficulty, vocab:w};
    } else if(type_ === 'article'){
      if(!w.art || w.art === '-'){ attempts++; continue; }
      ex = {skill:'articles', prompt:`Which article goes with "${w.de}"?`, promptHTML:`Which article goes with <b>${esc(w.de)}</b>? ${speakerBtn(w.de)}`,
        options:['der','die','das'], correct:w.art, explanation:`${w.art} ${w.de} = ${meaningFull(w)}`, sourceId:'v'+w.n, difficulty, vocab:w};
    } else if(type_ === 'listen'){
      const correct = w.de;
      const wrongPool = betterDistractors(w, distractorCount(difficulty), 'de');
      const options = shuffle([correct, ...wrongPool.map(x => x.de)]);
      const unique = [...new Set(options)];
      while(unique.length < distractorCount(difficulty)+1){
        const extra = VOCAB[Math.floor(Math.random()*VOCAB.length)].de;
        if(!unique.includes(extra)) unique.push(extra);
      }
      ex = {skill:'listening', prompt:'Listen and choose the correct German word.', promptHTML:`Listen and choose: <br><button class="btn small" onclick="speakGerman('${esc(w.de).replace(/'/g,"\'")}')">🔊 Play</button>`,
        options: unique.slice(0, distractorCount(difficulty)+1), correct, explanation:`The word was: ${speakText}`, sourceId:'v'+w.n, difficulty, vocab:w, autoPlay: w.de};
    } else if(type_ === 'opposite'){
      // Sample from OPPOSITES directly for reliability
      const pair = OPPOSITES[Math.floor(Math.random() * OPPOSITES.length)];
      const askFirst = Math.random() < 0.5;
      const promptWord = askFirst ? pair[0] : pair[2];
      const promptEn = askFirst ? pair[1] : pair[3];
      const correct = askFirst ? pair[2] : pair[0];
      const correctEn = askFirst ? pair[3] : pair[1];
      const wrongs = shuffle(OPPOSITES.filter(p => p[0] !== correct && p[2] !== correct && p[0] !== promptWord && p[2] !== promptWord)
        .map(p => Math.random()<0.5 ? p[0] : p[2])).slice(0, distractorCount(difficulty));
      const unique = [...new Set([correct, ...wrongs])];
      while(unique.length < distractorCount(difficulty)+1){
        const extra = OPPOSITES[Math.floor(Math.random()*OPPOSITES.length)];
        const cand = Math.random()<0.5 ? extra[0] : extra[2];
        if(!unique.includes(cand) && cand !== promptWord) unique.push(cand);
      }
      ex = {skill:'opposites', prompt:`What is the opposite of "${promptWord}"?`, promptHTML:`What is the opposite of <b>${esc(promptWord)}</b> (${esc(promptEn)})? ${speakerBtn(promptWord)}`,
        options: shuffle(unique.slice(0, distractorCount(difficulty)+1)), correct, explanation:`${promptWord} ↔ ${correct} (${correctEn})`, sourceId:'opp-'+promptWord, difficulty};
    } else if(type_ === 'synonym'){
      const entry = SYNONYMS[Math.floor(Math.random() * SYNONYMS.length)];
      // Ask for a synonym of the headword, or sometimes of one of the synonyms
      const useHead = Math.random() < 0.7 || entry.syn.length === 0;
      const promptWord = useHead ? entry.word : entry.syn[Math.floor(Math.random()*entry.syn.length)][0];
      const correct = useHead ? entry.syn[0][0] : entry.word;
      const allRelated = new Set([entry.word, ...entry.syn.map(x => x[0])]);
      const wrongs = shuffle(SYNONYMS.filter(s => s.word !== entry.word)
        .flatMap(s => [s.word, ...s.syn.map(x => x[0])]))
        .filter(x => !allRelated.has(x)).slice(0, distractorCount(difficulty));
      const unique = [...new Set([correct, ...wrongs])];
      while(unique.length < distractorCount(difficulty)+1){
        const extra = SYNONYMS[Math.floor(Math.random()*SYNONYMS.length)].word;
        if(!unique.includes(extra) && !allRelated.has(extra)) unique.push(extra);
      }
      ex = {skill:'synonyms', prompt:`Which word is a synonym of "${promptWord}"?`, promptHTML:`Which word is a synonym of <b>${esc(promptWord)}</b>? ${speakerBtn(promptWord)}`,
        options: shuffle(unique.slice(0, distractorCount(difficulty)+1)), correct, explanation:`${promptWord} ≈ ${correct}`, sourceId:'syn-'+promptWord, difficulty};
    }
    if(!ex){ attempts++; continue; }
    const fp = exerciseFingerprint(ex.prompt + '|' + ex.correct);
    if(!isDuplicate(fp)){ rememberFingerprint(fp); return ex; }
    attempts++;
  }
  // Safe fallback without dummy options
  const w = usePool[Math.floor(Math.random()*usePool.length)] || VOCAB[0];
  const speakText = (w.art && w.art !== '-' ? w.art + ' ' : '') + w.de;
  const wrongs = shuffle(VOCAB.filter(x => x.de !== w.de)).slice(0,2).map(x => meaningFull(x));
  return {skill:'vocabulary', prompt:`What does "${speakText}" mean?`, promptHTML:`What does <b>${esc(speakText)}</b> mean?`,
    options: shuffle([meaningFull(w), ...wrongs]), correct: meaningFull(w), explanation:`${speakText} = ${meaningFull(w)}`, sourceId:'v'+w.n, vocab:w};
}

/* ============================================================
   v5.4 INFINITE GENERATION ENGINE
   ============================================================ */
let __rng = Math.random;
function seededRandom(seed){
  let x = (seed | 0) || 0x9E3779B9;
  return () => { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; return (x >>> 0) / 4294967296; };
}
function setSeed(s){ __rng = seededRandom(s); }
function rnd(){ return __rng(); }
function rPick(a){ return a[Math.floor(rnd() * a.length)]; }
function cap(s){ return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }

const POOL = {
  namesM:['Peter','Thomas','Markus','David','Ali','Felix','Jonas','Lukas','Max','Klaus','Ahmed','Leon','Ben','Tim','Jan'],
  namesF:['Anna','Maria','Sarah','Lena','Sophie','Nina','Lea','Mia','Emma','Julia','Priya','Aisha','Clara','Laura','Hannah'],
  cities:['Berlin','München','Hamburg','Köln','Frankfurt','Stuttgart','Dresden','Wien','Zürich','Bremen','Leipzig','Nürnberg','Ahmedabad','Delhi','Mumbai'],
  times:['heute','morgen','am Montag','am Samstag','nächste Woche','letztes Wochenende','um 8 Uhr','um 19 Uhr','am Abend','am Morgen'],
  transport:['mit dem Zug','mit dem Bus','mit dem Auto','mit dem Fahrrad','mit der U-Bahn','mit dem Flugzeug','zu Fuß'],
  activities:['ein Museum besuchen','im Hotel bleiben','einen Film sehen','spazieren gehen','Kaffee trinken','ein Buch lesen','Sport machen','Musik hören','Freunde treffen','Fotos machen'],
  problems:['der Zug hat Verspätung','das Hotelzimmer ist zu klein','das Wetter ist schlecht','das Restaurant ist geschlossen','der Bus kommt nicht','die Rechnung ist zu hoch'],
  feelings:['glücklich','müde','zufrieden','aufgeregt','entspannt','überrascht'],
  greetings:['Hallo','Guten Morgen','Guten Tag','Guten Abend']
};

const CONJ = {
  sein:{ich:'bin',du:'bist',er:'ist',sie:'ist',wir:'sind'},
  haben:{ich:'habe',du:'hast',er:'hat',sie:'hat',wir:'haben'},
  wohnen:{ich:'wohne',du:'wohnst',er:'wohnt',sie:'wohnt',wir:'wohnen'},
  arbeiten:{ich:'arbeite',du:'arbeitest',er:'arbeitet',sie:'arbeitet',wir:'arbeiten'},
  fahren:{ich:'fahre',du:'fährst',er:'fährt',sie:'fährt',wir:'fahren'},
  gehen:{ich:'gehe',du:'gehst',er:'geht',sie:'geht',wir:'gehen'},
  kommen:{ich:'komme',du:'kommst',er:'kommt',sie:'kommt',wir:'kommen'},
  aufstehen:{ich:'stehe auf',du:'stehst auf',er:'steht auf',sie:'steht auf'},
  lesen:{ich:'lese',du:'liest',er:'liest',sie:'liest',wir:'lesen'},
  trinken:{ich:'trinke',du:'trinkst',er:'trinkt',sie:'trinkt',wir:'trinken'},
  kochen:{ich:'koche',du:'kochst',er:'kocht',sie:'kocht',wir:'kochen'},
  sehen:{ich:'sehe',du:'siehst',er:'sieht',sie:'sieht',wir:'sehen'},
  besuchen:{ich:'besuche',du:'besuchst',er:'besucht',sie:'besucht',wir:'besuchen'},
  kaufen:{ich:'kaufe',du:'kaufst',er:'kauft',sie:'kauft',wir:'kaufen'}
};
function conj(inf, p){ const c = CONJ[inf]; return c && c[p] ? c[p] : inf; }

function generateScenario(level, topic){
  const isF = rnd() < 0.5;
  const name = rPick(isF ? POOL.namesF : POOL.namesM);
  const pronoun = isF ? 'sie' : 'er';
  const city = rPick(POOL.cities);
  let dest = rPick(POOL.cities); let g = 0;
  while(dest === city && g++ < 5) dest = rPick(POOL.cities);
  return {name, pronoun, isF, city, dest, time: rPick(POOL.times), transport: rPick(POOL.transport),
    activity: rPick(POOL.activities), problem: rPick(POOL.problems), feeling: rPick(POOL.feelings),
    level: level || 'A2', topic: topic || 'daily-life'};
}

function generateReadingTask(level, topic){
  level = level || rPick(['A1','A2','B1']);
  const s = generateScenario(level, topic);
  const sn = [];
  if(level === 'A1'){
    sn.push(`${s.name} wohnt in ${s.city}.`);
    sn.push(`${cap(s.pronoun)} ${conj('aufstehen', s.pronoun)} um sieben Uhr auf.`);
    sn.push(`Danach frühstückt ${s.pronoun}.`);
    sn.push(`${cap(s.time)} ${conj('fahren', s.pronoun)} ${s.pronoun} ${s.transport} nach ${s.dest}.`);
    sn.push(`${cap(s.pronoun)} möchte ${s.activity}.`);
    sn.push(`Am Ende ist ${s.pronoun} ${s.feeling}.`);
  } else if(level === 'A2'){
    sn.push(`${s.name} wohnt in ${s.city} und arbeitet dort.`);
    sn.push(`Letztes Wochenende ist ${s.pronoun} ${s.transport} nach ${s.dest} gefahren.`);
    sn.push(`${cap(s.pronoun)} wollte ${s.activity}.`);
    sn.push(`Leider gab es ein Problem: ${s.problem}.`);
    sn.push(`Trotzdem war ${s.pronoun} am Ende ${s.feeling}.`);
    sn.push(`${cap(s.pronoun)} möchte nächste Woche wieder dorthin fahren.`);
  } else {
    sn.push(`${s.name} lebt seit einigen Jahren in ${s.city}.`);
    sn.push(`Obwohl ${s.pronoun} gerne reist, hat ${s.pronoun} nur selten Zeit dafür.`);
    sn.push(`Letztes Wochenende ist ${s.pronoun} jedoch ${s.transport} nach ${s.dest} gefahren.`);
    sn.push(`Während der Fahrt gab es ein Problem: ${s.problem}.`);
    sn.push(`Trotzdem konnte ${s.pronoun} am Ende ${s.activity}.`);
    sn.push(`Wenn ${s.pronoun} mehr Zeit hätte, würde ${s.pronoun} öfter solche Reisen machen.`);
    sn.push(`Nach der Reise war ${s.pronoun} zwar erschöpft, aber auch sehr ${s.feeling}.`);
  }
  const text = sn.join(' ');
  const qs = [
    [`Wo wohnt ${s.name}?`, `In ${s.city}.`],
    [`Wohin ist ${s.name} gefahren?`, `Nach ${s.dest}.`],
    [`Wie ist ${s.name} gefahren?`, `${cap(s.transport)}.`],
    [`Was wollte ${s.name} machen?`, `${cap(s.activity)}.`],
    [`Wie war ${s.name} am Ende?`, `${s.pronoun} war ${s.feeling}.`]
  ];
  S.readingsGenerated = (S.readingsGenerated||0) + 1; STORE.save(); checkAchievements();
  return {level, topic: s.topic, title:`${s.name} reist nach ${s.dest}`, text, qs, scenario: s};
}

function generateDialogueTask(level, topic){
  level = level || rPick(['A1','A2','B1']);
  const s = generateScenario(level, topic);
  const friend = rPick(s.isF ? POOL.namesM : POOL.namesF);
  const greeting = rPick(POOL.greetings);
  const lines = [];
  if(level === 'A1'){
    lines.push({sp:s.name, de:`${greeting}, ${friend}!`, en:`${greeting}, ${friend}!`});
    lines.push({sp:friend, de:`Hallo ${s.name}! Wie geht es dir?`, en:`Hello ${s.name}! How are you?`});
    lines.push({sp:s.name, de:`Mir geht es gut, danke. Ich fahre ${s.time} nach ${s.dest}.`, en:`I am well, thanks. I am going to ${s.dest} ${s.time}.`});
    lines.push({sp:friend, de:`Schön! ${cap(s.transport)}?`, en:`Nice! ${cap(s.transport)}?`});
    lines.push({sp:s.name, de:`Ja, genau. Ich möchte ${s.activity}.`, en:`Yes, exactly. I want to ${s.activity}.`});
    lines.push({sp:friend, de:`Viel Spaß!`, en:`Have fun!`});
  } else if(level === 'A2'){
    lines.push({sp:s.name, de:`${greeting}! Wie war dein Wochenende?`, en:`${greeting}! How was your weekend?`});
    lines.push({sp:friend, de:`Ganz gut, danke. Ich bin ${s.transport} nach ${s.dest} gefahren.`, en:`Pretty good, thanks. I went to ${s.dest} ${s.transport}.`});
    lines.push({sp:s.name, de:`Wirklich? Was hast du dort gemacht?`, en:`Really? What did you do there?`});
    lines.push({sp:friend, de:`Ich habe ${s.activity} können.`, en:`I was able to ${s.activity}.`});
    lines.push({sp:s.name, de:`Und gab es Probleme?`, en:`And were there any problems?`});
    lines.push({sp:friend, de:`Leider ja: ${s.problem}.`, en:`Unfortunately yes: ${s.problem}.`});
    lines.push({sp:s.name, de:`Oh nein! Aber sonst war alles gut?`, en:`Oh no! But otherwise everything was good?`});
    lines.push({sp:friend, de:`Ja, am Ende war ich trotzdem ${s.feeling}.`, en:`Yes, in the end I was still ${s.feeling}.`});
  } else {
    lines.push({sp:'Moderator', de:`Willkommen zur Sendung. Heute sprechen wir über Reisen.`, en:`Welcome. Today we talk about travel.`});
    lines.push({sp:s.name, de:`Ich reise sehr gerne, obwohl ich nur selten Zeit habe.`, en:`I love to travel, although I rarely have time.`});
    lines.push({sp:'Moderator', de:`Erzählen Sie uns von Ihrer letzten Reise.`, en:`Tell us about your last trip.`});
    lines.push({sp:s.name, de:`Letztes Wochenende bin ich ${s.transport} nach ${s.dest} gefahren.`, en:`Last weekend I went to ${s.dest} ${s.transport}.`});
    lines.push({sp:s.name, de:`Während der Fahrt gab es ein Problem: ${s.problem}.`, en:`During the trip there was a problem: ${s.problem}.`});
    lines.push({sp:'Moderator', de:`Wie sind Sie damit umgegangen?`, en:`How did you deal with it?`});
    lines.push({sp:s.name, de:`Trotzdem konnte ich ${s.activity}. Danach war ich sehr ${s.feeling}.`, en:`Nevertheless I could ${s.activity}. Afterwards I was very ${s.feeling}.`});
    lines.push({sp:'Moderator', de:`Vielen Dank für das Gespräch!`, en:`Thank you very much!`});
  }
  const q1C = s.dest, q1W = shuffle(POOL.cities.filter(c => c !== q1C)).slice(0,2);
  const q2C = s.transport, q2W = shuffle(POOL.transport.filter(x => x !== q2C)).slice(0,2);
  const q3C = s.feeling, q3W = shuffle(POOL.feelings.filter(x => x !== q3C)).slice(0,2);
  const questions = [
    {q:`Wohin ist ${s.name} gefahren?`, options: shuffle([q1C, ...q1W]), correct: q1C},
    {q:`Wie ist ${s.name} gefahren?`, options: shuffle([q2C, ...q2W]), correct: q2C},
    {q:`Wie war ${s.name} am Ende?`, options: shuffle([q3C, ...q3W]), correct: q3C}
  ];
  return {level, title:`Dialog: ${s.name} reist nach ${s.dest}`, setting:`A ${level} dialogue about travel.`, lines, questions, scenario: s};
}

function generateSpeakingTask(level, topic){
  level = level || rPick(['A1','A2','B1']);
  const s = generateScenario(level, topic);
  const patterns = level === 'A1'
    ? [`Ich heiße …`, `Ich komme aus …`, `Ich wohne in …`, `Ich fahre ${s.time} nach ${s.dest}.`, `Ich möchte ${s.activity}.`]
    : level === 'A2'
    ? [`Letztes Wochenende bin ich ${s.transport} nach ${s.dest} gefahren.`, `Ich wollte ${s.activity}.`, `Es gab ein Problem: …`, `Trotzdem war ich am Ende …`]
    : [`Obwohl ich gerne reise, habe ich nur selten Zeit.`, `Letztes Wochenende bin ich … gefahren, weil …`, `Während der Fahrt …`, `Wenn ich mehr Zeit hätte, würde ich …`];
  const vocab = ['reisen','fahren','wohnen','möchten','Problem','Wochenende','Zug','Wetter'];
  const model = level === 'A1'
    ? `Hallo, ich heiße ${s.name}. Ich wohne in ${s.city}. ${cap(s.time)} fahre ich ${s.transport} nach ${s.dest}. Ich möchte ${s.activity}.`
    : level === 'A2'
    ? `Letztes Wochenende bin ich ${s.transport} nach ${s.dest} gefahren. Ich wollte ${s.activity}. Leider gab es ein Problem: ${s.problem}. Trotzdem war ich am Ende ${s.feeling}.`
    : `Obwohl ich gerne reise, habe ich nur selten Zeit. Letztes Wochenende bin ich ${s.transport} nach ${s.dest} gefahren. Während der Fahrt gab es ein Problem: ${s.problem}. Trotzdem konnte ich ${s.activity}. Am Ende war ich ${s.feeling}.`;
  const checklist = ['Flüssig gesprochen','Korrekte Verben','Zeitform korrekt','Mindestens 5 Sätze','Verbindungswörter'];
  return {level, topic: s.topic, title:`Sprechen: Reise nach ${s.dest}`, patterns, vocab, model, checklist, scenario: s};
}

function generateWritingTask(level, topic, type){
  level = level || rPick(['A1','A2','B1']);
  type = type || rPick(['email','forum','beschwerde']);
  const s = generateScenario(level, topic);
  const friend = rPick(s.isF ? POOL.namesM : POOL.namesF);
  S.writingsDone = (S.writingsDone||0) + 1; STORE.save(); checkAchievements();
  if(type === 'email'){
    const required = level === 'A1'
      ? ['Anrede','Grund (Reise)','Datum','Grußformel']
      : ['Anrede','Wohin gereist','Transportmittel','Aktivität','Wetter/Problem','Grußformel'];
    const model = level === 'A1'
      ? `Liebe/r ${friend},\n\nich fahre ${s.time} nach ${s.dest}. Ich fahre ${s.transport}. Ich möchte ${s.activity}.\n\nLiebe Grüße\n${s.name}`
      : `Liebe/r ${friend},\n\nletztes Wochenende bin ich ${s.transport} nach ${s.dest} gefahren. Ich wollte ${s.activity}. Leider gab es ein Problem: ${s.problem}. Trotzdem war ich am Ende ${s.feeling}.\n\nLiebe Grüße\n${s.name}`;
    return {level, type:'E-Mail', title:`E-Mail an ${friend} über ${s.dest}`,
      prompt:`Schreibe ${friend} eine E-Mail über deine Reise nach ${s.dest}.`,
      required, model, minWords: level === 'A1' ? 40 : 70};
  }
  if(type === 'forum'){
    return {level, type:'Forum', title:`Forumsbeitrag über Reisen`,
      prompt:`Schreibe einen Forumsbeitrag über die Vor- und Nachteile des Reisens.`,
      required:['Einleitung','Vorteil','Nachteil','Eigene Meinung','Schluss'],
      model:`Meiner Meinung nach hat Reisen sowohl Vorteile als auch Nachteile.\n\nEinerseits lernt man neue Kulturen kennen. Andererseits ist es oft teuer.\n\nIch finde, Reisen lohnt sich trotzdem immer.`, minWords:80};
  }
  return {level, type:'Beschwerde', title:`Beschwerde über ${s.problem}`,
    prompt:`Du hattest ein Problem: ${s.problem}. Schreibe eine Beschwerde-E-Mail.`,
    required:['Formelle Anrede','Problem beschrieben','Lösung gefordert','Grußformel'],
    model:`Sehr geehrte Damen und Herren,\n\nich schreibe Ihnen, weil ${s.problem}.\n\nIch bitte Sie um eine schnelle Lösung.\n\nMit freundlichen Grüßen\n${s.name}`, minWords:60};
}

function generateVerbUsageExercise(){
  const keys = Object.keys(VERB_USAGE || {});
  if(!keys.length) return generateVocabExercise('de-en');
  const k = rPick(keys);
  const u = VERB_USAGE[k];
  const pattern = rPick(u.patterns);
  const words = pattern.split(/\s+/);
  const candidates = words.map((w,i) => ({w, i})).filter(x => x.w.length > 2 && /^[a-zäöüß]/i.test(x.w));
  if(!candidates.length) return generateVocabExercise('de-en');
  const blank = rPick(candidates);
  const prompt = words.map((w,i) => i === blank.i ? '___' : w).join(' ');
  const correct = blank.w;
  const wrongPool = [];
  keys.forEach(kk => VERB_USAGE[kk].patterns.forEach(p => p.split(/\s+/).forEach(w => {
    if(w !== correct && w.length > 3 && !wrongPool.includes(w)) wrongPool.push(w);
  })));
  while(wrongPool.length < 3) wrongPool.push('gehen');
  return {
    skill:'verb-usage', topic:'verb usage', level:'A2',
    promptHTML:`Which word completes: <b>${esc(prompt)}</b>?<br><em class="mini-muted">Verb: ${esc(k)} (${esc(u.meaning)})</em>`,
    prompt:`Complete: ${prompt} (verb: ${k})`,
    options: shuffle([correct, ...shuffle(wrongPool).slice(0,3)]),
    correct, explanation:`${pattern} — from verb ${k}`, sourceId:'verb-'+k
  };
}

function generateGrammarExerciseLadder(level, difficulty){
  const sections = level && level !== 'all' ? GRAMMAR_DATA.filter(s => s.level === level) : GRAMMAR_DATA;
  const section = rPick(sections);
  const item = rPick(section.items);
  const diff = difficulty || 'normal';

  if(diff === 'expert' && item.mistakes && item.mistakes.length){
    const pair = rPick(item.mistakes);
    const bad = pair[0].replace(/^❌\s*/, '');
    const correct = pair[1].replace(/^✅\s*/, '');
    const distractors = item.mistakes.filter(p => p !== pair).map(p => p[0].replace(/^❌\s*/, ''));
    while(distractors.length < 3) distractors.push(correct.replace(/[a-zäöü]/g, m => m.toUpperCase()));
    return {
      skill:'grammar', topic:item.title, level:section.level,
      promptHTML:`Correct this sentence:<br><b>${esc(bad)}</b>`,
      prompt:`Correct: ${bad}`,
      options: shuffle([correct, ...shuffle(distractors).slice(0,3)]),
      correct, explanation: item.explanation, sourceId:'gx-'+section.level+'-'+item.title
    };
  }

  if(item.examples && item.examples.length){
    const ex = rPick(item.examples);
    const de = ex[0], en = ex[1];
    const words = de.split(/\s+/);
    const candidates = [];
    words.forEach((w, i) => {
      const c = w.replace(/[.,!?;:]/g, '');
      if(i > 0 && c.length > 3 && !/^\d+$/.test(c)) candidates.push(i);
    });
    if(candidates.length){
      const blankIdx = rPick(candidates);
      const correct = words[blankIdx].replace(/[.,!?;:]/g, '');
      const prompt = words.map((w, i) => i === blankIdx ? '___' : w).join(' ');
      const wrongs = [];
      item.examples.forEach(e => e[0].split(/\s+/).forEach(w => {
        const c = w.replace(/[.,!?;:]/g, '');
        if(c !== correct && c.length > 2 && !wrongs.includes(c)) wrongs.push(c);
      }));
      if(wrongs.length < 3){
        section.items.forEach(it => (it.examples || []).forEach(e => e[0].split(/\s+/).forEach(w => {
          const c = w.replace(/[.,!?;:]/g, '');
          if(c !== correct && c.length > 2 && !wrongs.includes(c)) wrongs.push(c);
        })));
      }
      while(wrongs.length < 3) wrongs.push('gehen');
      return {
        skill:'grammar', topic:item.title, level:section.level,
        promptHTML:`${esc(prompt)}<br><em class="mini-muted">${esc(en)}</em>`,
        prompt,
        options: shuffle([correct, ...shuffle(wrongs).slice(0,3)]),
        correct, explanation:`${correct} → "${de}"`, sourceId:'g-'+section.level+'-'+item.title
      };
    }
  }
  const ex = item.exercise;
  const correct = ex.options[ex.correct];
  return {
    skill:'grammar', topic:item.title, level:section.level,
    promptHTML:esc(ex.q), prompt:ex.q,
    options: shuffle([...ex.options]), correct,
    explanation: ex.why, sourceId:'g-'+section.level+'-'+item.title
  };
}

function generateConnectorExercise(c){
  const options = ['main clause — verb position 2', 'subordinate clause — verb at end', 'adverb — verb next'];
  const correct = c.clause === 'main' ? (c.order === 'position-2-verb-next' || c.order === 'verb-position-2' ? 2 : 0) : 1;
  return {
    prompt: `"${c.word}" (${c.meaning}) — how is it used?`,
    promptHTML: `<b>${esc(c.word)}</b> (${esc(c.meaning)}) — clause type?`,
    options, correct: options[correct],
    explanation: `${c.word} — ${c.clause}, ${c.order}`,
    connector: c
  };
}
function generateCollocationExercise(c){
  const allVerbs = shuffle(COLLOCATIONS.map(x => x.verb).filter(v => v !== c.verb)).slice(0, 3);
  const options = shuffle([c.verb, ...allVerbs]);
  const prompt = c.phrase.replace(new RegExp('\\b' + c.verb + '\\b'), '___');
  return {
    prompt: `Which verb completes: "${prompt}"?`,
    promptHTML: `Which verb completes <b>${esc(prompt)}</b>?`,
    options, correct: c.verb,
    explanation: `${c.phrase} — ${c.en}`,
    collocation: c
  };
}
function generateComparisonExercise(c){
  const idx = rnd() < 0.5 ? 0 : 1;
  const ex = c.examples[idx];
  const correct = idx === 0 ? c.a : c.b;
  const other = idx === 0 ? c.b : c.a;
  return {
    prompt: ex, promptHTML: ex.replace('___', '<b>___</b>'),
    options: shuffle([correct, other]), correct,
    explanation: idx === 0 ? c.aEx : c.bEx,
    note: c.note, comparison: c
  };
}
function generateSentenceBuilderExercise(level){
  const lvl = level && level !== 'all' ? level : rPick(['A1','A2','B1']);
  const subj = rPick([['Ich','I'], ['Du','You'], ['Er','He'], ['Sie','She'], ['Wir','We'], ['Ihr','You (pl)']]);
  const nouns = VOCAB.filter(w => ['der','die','das'].includes(w.art) && w.level === lvl);
  const poolN = nouns.length ? nouns : VOCAB.filter(w => ['der','die','das'].includes(w.art));
  const obj = rPick(poolN);
  // Accusative article adjustment for common verbs that take Akk
  const artMap = {der:'den', die:'die', das:'das'};
  const akkArt = artMap[obj.art] || obj.art;
  const verbTable = {
    A1: [
      ['gehe','go', false], ['komme','come', false], ['lerne','learn', true], ['spiele','play', true],
      ['esse','eat', true], ['trinke','drink', true], ['sehe','see', true], ['höre','hear', true]
    ],
    A2: [
      ['habe','have', true], ['kaufe','buy', true], ['brauche','need', true], ['suche','look for', true],
      ['finde','find', true], ['nehme','take', true], ['lese','read', true], ['schreibe','write', true]
    ],
    B1: [
      ['besuche','visit', true], ['verstehe','understand', true], ['kenne','know', true],
      ['erkläre','explain', true], ['vergleiche','compare', true], ['beschreibe','describe', true]
    ]
  };
  const verbs = verbTable[lvl] || verbTable.A1;
  const pair = rPick(verbs);
  const conjForm = pair[0], infEn = pair[1], takesAkk = pair[2];
  // Simple person agreement for a few irregulars is already in the forms (ich-forms mostly; adjust for du/er)
  let conj = conjForm;
  if(subj[0] === 'Du'){
    if(conjForm.endsWith('e') && !conjForm.endsWith('ie')) conj = conjForm.slice(0,-1) + 'st';
    else if(conjForm === 'habe') conj = 'hast';
    else if(conjForm === 'gehe') conj = 'gehst';
    else if(conjForm === 'komme') conj = 'kommst';
    else if(conjForm === 'sehe') conj = 'siehst';
    else if(conjForm === 'nehme') conj = 'nimmst';
    else if(conjForm === 'lese') conj = 'liest';
  } else if(subj[0] === 'Er' || subj[0] === 'Sie'){
    if(conjForm.endsWith('e') && !conjForm.endsWith('ie')) conj = conjForm.slice(0,-1) + 't';
    else if(conjForm === 'habe') conj = 'hat';
    else if(conjForm === 'gehe') conj = 'geht';
    else if(conjForm === 'komme') conj = 'kommt';
    else if(conjForm === 'sehe') conj = 'sieht';
    else if(conjForm === 'nehme') conj = 'nimmt';
    else if(conjForm === 'lese') conj = 'liest';
  } else if(subj[0] === 'Wir'){
    conj = conjForm.endsWith('e') ? conjForm.slice(0,-1) + 'en' : conjForm + 'en';
    if(conjForm === 'habe') conj = 'haben';
    if(conjForm === 'sehe') conj = 'sehen';
    if(conjForm === 'nehme') conj = 'nehmen';
    if(conjForm === 'lese') conj = 'lesen';
  } else if(subj[0] === 'Ihr'){
    if(conjForm.endsWith('e')) conj = conjForm.slice(0,-1) + 't';
    if(conjForm === 'habe') conj = 'habt';
    if(conjForm === 'sehe') conj = 'seht';
    if(conjForm === 'nehme') conj = 'nehmt';
    if(conjForm === 'lese') conj = 'lest';
  }
  const art = takesAkk ? akkArt : obj.art;
  const answer = `${subj[0]} ${conj} ${art} ${obj.de}.`;
  const en = `${subj[1]} ${infEn} the ${obj.en}.`;
  const tokens = shuffle([subj[0], conj, art, obj.de + '.']);
  return {level: lvl, answer, en, tokens};
}

function generateDictationExercise(level){
  const pool = [];
  PATTERNS.forEach(p => pool.push({de: p[3], en: p[4], level: 'A1'}));
  GRAMMAR_DATA.forEach(s => s.items.forEach(it => it.examples.forEach(e => pool.push({de: e[0], en: e[1], level: s.level}))));
  const filtered = level && level !== 'all' ? pool.filter(p => p.level === level) : pool;
  const item = rPick(filtered.length ? filtered : pool);
  return {level: item.level, de: item.de, en: item.en || ''};
}

