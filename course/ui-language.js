/* Source module: ui-language.js
 * UI text, translations, and common text helpers.
 * Build: scripts/build-course.py concatenates modules in its declared order.
 */
/* ============================================================
   TRANSLATIONS (compact)
   ============================================================ */
const UI = {
  en: {
    nav_home:'🏠 Today', nav_session:'⚡ Session', nav_review:'🧠 Review', nav_vocab:'📚 Vocab',
    nav_grammar:'📖 Grammar', nav_quiz:'🎯 Quiz', nav_flash:'🧠 Cards', nav_verbs:'🔥 Verbs',
    nav_connectors:'🔗 Connectors', nav_collocations:'🧱 Collocations', nav_compare:'⚖️ Compare',
    nav_mistakes:'❌ Mistakes', nav_sentence:'🧩 Sentences', nav_spelling:'✏️ Spelling',
    nav_dictation:'📝 Dictation', nav_families:'🌳 Families', nav_articles:'📖 Articles',
    nav_pronounce:'🔤 Pron', nav_synonyms:'↔️ Opposites', nav_patterns:'🗣️ Patterns',
    nav_listen:'🎧 Listen', nav_speak:'🎤 Speak', nav_read:'📕 Read', nav_write:'✍️ Write',
    nav_exam:'🎓 Exam', nav_resources:'🔗 Resources', nav_progress:'📊 Progress', nav_settings:'⚙️ Settings',
    home_title:'🇩🇪 German A1 → B1 · v5.4',
    home_desc:'Infinite practice engine · SRS · mistake tracking · guided sessions',
    study_modules:'Modules', stat_words:'Words', stat_known:'Mastered', stat_due:'Due', stat_streak:'Streak',
    vocab_search:'🔎 Search German or English…', all_topics:'All topics', all_articles:'All articles', all_levels:'All levels',
    no_words:'No matches.', quiz_title:'🎯 Quiz', quiz_sub:'Auto-generated infinitely.',
    quiz_article:'Article', quiz_de_en:'DE → EN', quiz_en_de:'EN → DE',
    round_complete:'Round complete!', question_of:(i,t) => `Q <b>${i}</b> / ${t}`, score_label:s => `Score <b>${s}</b>`,
    correct:'✅ Correct!', correct_answer:a => `❌ Correct: <b>${a}</b>.`, play_again:'Play again',
    verbs_title:'🔥 Verbs', patterns_title:'🗣️ Patterns', grammar_title:'📖 Grammar',
    listen_title:'🎧 Listening', speak_title:'🎤 Speaking', read_title:'📕 Reading', write_title:'✍️ Writing',
    res_title:'🔗 Resources', prog_title:'📊 Progress',
    session_title:'⚡ Daily Session', session_start:'▶ Start', session_complete:'🎉 Session complete',
    review_title:'🧠 Smart Review', review_start:'▶ Start review', mistakes_title:'❌ Mistakes',
    mistakes_empty:'No mistakes yet.', families_title:'🌳 Word Families', sentence_title:'🧩 Sentence Builder',
    spelling_title:'✏️ Spelling', dictation_title:'📝 Dictation', exam_title:'🎓 Exam',
    connectors_title:'🔗 Connectors', collocations_title:'🧱 Collocations', compare_title:'⚖️ Verb Compare',
    settings_title:'⚙️ Settings', settings_sub:'Preferences saved on this device.',
    setup_count:'Questions', setup_difficulty:'Difficulty',
    diff_easy:'🟢 Easy', diff_normal:'🟡 Normal', diff_hard:'🟠 Hard', diff_expert:'🔴 Expert', diff_mixed:'🎲 Mixed',
    generate_more:'⚡ Generate more', practice_inf:'⚡ Practice ∞', new_item:'🔄 New',
    save_ok:'✓ Saved', all:'All'
  }
};
function t(key, ...args){
  const dict = UI.en;
  const v = (dict[key] !== undefined) ? dict[key] : UI.en[key];
  if(v === undefined) return key;
  return (typeof v === 'function') ? v(...args) : v;
}

function meaningFull(w){ return w.en; }

/* ============================================================
   VOCABULARY
   ⚠️ REPLACE THIS BLOCK with your full 3008-word TOPICS array from v4/v5.
   The structure is: [topicName, level, "n|art|de|en\n..."]
   ============================================================ */
