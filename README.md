# Sprachtreppe — German A1–C2 (expansion in progress)

A practical German-learning companion being expanded from **A1 through C2**: structured grammar notes, searchable vocabulary, examples, common-mistake guidance, sentence connectors, verb–preposition pairs, email/letter templates, interactive exercises, and an offline-first Android/web course.

Use the Markdown notes for quick revision on GitHub, then practise the same grammar and vocabulary in the app. The material follows common CEFR A1–B1 learning goals and can be used alongside textbooks such as *Netzwerk neu*. It is independent supplementary material, not an official Hueber publication; exact chapter numbering depends on your book edition.

## A1–C2 expansion status

The feature branch `feature/cefr-a1-c2-expansion` adds starter B2, C1 and C2 grammar lessons and a small advanced vocabulary seed set. The existing A1–B1 lessons, offline app, Android shell and Supabase classroom system are retained. This is an incremental expansion: the complete C2 curriculum and a comprehensive German lexicon are still future content work. See the [A1–C2 expansion plan](docs/roadmap/A1_C2_EXPANSION_PLAN.md).

## Table of contents

- [A1 — Build the foundations](#a1)
- [A2 — Join ideas and describe experiences](#a2)
- [B1 — Explain, compare and argue clearly](#b1)
- [Quick grammar reference](#quick-grammar-reference)
- [Vocabulary and self-tests](#vocabulary-and-self-tests)
- [Email and letter templates](docs/writing/01_Email_and_Letter_Templates.md)
- [Source layout and development](#source-layout-and-development)

## A1

Start with sentence structure, present tense, articles, cases, everyday questions and negation. Learn nouns with their articles and practise a few complete sentences every day.

**Open the guide:** [A1 Grammar Notes](docs/grammar/01_A1.md)

Topics include: `sein` and `haben`, personal pronouns and verb endings, articles, nominative and accusative, first dative patterns, modal verbs, separable verbs, `nicht` vs. `kein`, questions, word order, imperatives, and the spoken past with Perfekt.

<details>
<summary><b>A1 mini self-test — reveal the answers</b></summary>

1. Heute ___ ich Deutsch. (lernen)  
2. Ich habe ___ Auto. (kein / nicht)  
3. Wo ___ du? (wohnen)

<details>
<summary>Answers and reasons</summary>

1. **lerne** — the conjugated verb stays in position 2.  
2. **kein** — negate an indefinite noun phrase.  
3. **wohnst** — du takes the -st ending.

</details>
</details>

## A2

At A2, practise linking sentences and controlling case endings. Do not only memorise the English meaning of a connector; memorise what happens to the German verb.

**Open the guide:** [A2 Grammar Notes](docs/grammar/02_A2.md)

Topics include: `weil`, `dass`, `wenn` vs. `als`, indirect questions with `ob` and W-words, `deshalb` and `trotzdem`, modal verbs in Präteritum, Konjunktiv II requests, adjective endings, reflexive verbs, comparison, two-way prepositions, verb–preposition pairs, and infinitive clauses with `zu`.

<details>
<summary><b>A2 mini self-test — reveal the answers</b></summary>

1. Ich bleibe zu Hause, weil ich krank ___.  
2. Ich weiß nicht, ___ sie heute kommt.  
3. Das Auto ist schneller ___ der Bus.

<details>
<summary>Answers and reasons</summary>

1. **bin** — subordinate clause: finite verb at the end.  
2. **ob** — indirect yes/no question.  
3. **als** — comparative + als.

</details>
</details>

## B1

At B1, work on longer explanations, past-event order, reported speech, passive sentences and well-organised writing. Connectors make your message clear only when the clause order is also correct.

**Open the guide:** [B1 Grammar Notes](docs/grammar/03_B1.md)

Topics include: Plusquamperfekt, past Konjunktiv II, passive with modal verbs, indirect speech, genitive, n-declension, relative clauses with prepositions, two-part connectors, purpose clauses, Futur I assumptions, participles as adjectives, and the difference between a process and its resulting state.

## Quick grammar reference

### Connectors and word order

| Connector | Meaning | Word order | Example |
|---|---|---|---|
| `weil` | because | subordinate clause; verb at end | Ich lerne, weil ich morgen eine Prüfung **habe**. |
| `dass` | that | subordinate clause; verb at end | Ich glaube, dass er heute **kommt**. |
| `obwohl` | although | subordinate clause; verb at end | Obwohl es **regnet**, gehe ich spazieren. |
| `wenn` | if / whenever | subordinate clause; verb at end | Wenn ich Zeit **habe**, rufe ich dich an. |
| `deshalb` | therefore | main clause; verb in position 2 | Es regnet. Deshalb **bleibe** ich zu Hause. |
| `trotzdem` | nevertheless | main clause; verb in position 2 | Ich bin müde. Trotzdem **lerne** ich. |
| `damit` | so that | subordinate clause; verb at end | Ich spreche langsam, damit du mich **verstehst**. |
| `um ... zu` | in order to | infinitive at end; normally same subject | Ich lerne, um die Prüfung zu **bestehen**. |

### Common verb–preposition pairs

| Pair | Case | Example |
|---|---|---|
| warten **auf** | Akkusativ | Ich warte auf **den Bus**. |
| denken **an** | Akkusativ | Ich denke an **meine Prüfung**. |
| sich interessieren **für** | Akkusativ | Sie interessiert sich für **Musik**. |
| sprechen **mit** | Dativ | Ich spreche mit **meinem Lehrer**. |
| teilnehmen **an** | Dativ | Wir nehmen an **dem Kurs** teil. |
| helfen | Dativ | Ich helfe **meiner Freundin**. |

Learn each fixed pair as a chunk: **verb + preposition + case + example sentence**.

## Vocabulary and self-tests

- The app includes a searchable topic-based vocabulary bank and lets you practise articles, flashcards, synonyms/opposites and pronunciation.
- A short Markdown starter list is available in [Vocabulary Quick Lists](docs/vocabulary/README.md).
- Use the `<details>` self-tests in each guide for quick revision right on GitHub.
- Keep PDFs or exported learning decks in a dedicated `assets/` or `pdf/` folder if you add them later. Editable core notes belong in Markdown first.

## Source layout and development

The app's course source is modular. **Edit files under `course/`, not the generated `www/index.html`.** The build combines the source files into one offline-friendly HTML bundle for the website/PWA and Capacitor Android app.

| File | Responsibility |
|---|---|
| `course/template.html` | Page skeleton and mount points |
| `course/base.css`, `course/theme.css` | Main UI styling and theme refinements |
| `course/ui-language.js` | Interface text and translations |
| `course/vocabulary-data.js`, `course/advanced-vocabulary-data.js` | A1–B1 vocabulary and B2–C2 starter entries |
| `course/word-reference-data.js` | Pronunciation rules, synonyms and opposites |
| `course/grammar-reference-data.js`, `course/grammar-expansion.js`, `course/advanced-cefr-content.js` | A1–B1 lessons, teaching notes and B2–C2 starter lessons |
| `course/phrase-reference-data.js`, `course/achievement-data.js` | Verb patterns, connectors, word families, resources and achievements |
| `course/core-engine.js`, `course/exercise-registry.js` | State, mastery, exercise generation and exercise routing |
| `course/views-dashboard.js` | Home, sessions, review and mistakes |
| `course/views-vocabulary.js` | Vocabulary, articles, flashcards, quizzes and word references |
| `course/views-grammar.js` | Grammar lessons and checks |
| `course/views-communication.js` | Listening, speaking, reading and writing |
| `course/views-practice.js` | Connectors, exams, resources and progress |
| `course/settings-boot.js` | Settings and app startup |
| `course/auth-sync.js`, `course/lms-ui.js` | Authentication, weekly sync, student review, classes, assignments and staff-only navigation |
| `scripts/build-course.py` | Validates and bundles source files into `www/` |
| `scripts/build-course-lms.py` | Builds the course and injects the LMS screens |
| `backend/schema.sql` | Database schema and access-control rules |

### Build and test

```bash
npm ci
npm test
SUPABASE_URL="https://YOUR_PROJECT.supabase.co" SUPABASE_ANON_KEY="YOUR_PUBLIC_ANON_KEY" python3 scripts/build-course-lms.py
```

The build must use the Supabase **anon/publishable** key; never place a service-role secret in the app. GitHub Actions also runs the test suite before producing the Android APK. To deploy the public website, merge the approved change to `main` and check the website workflow.

### Roles

- **Student:** learn and practise, see assignments and announcements, and sync progress while online.
- **Teacher:** see assigned classes, publish work and announcements, and review assignment progress. Learning/exercise tabs are hidden and blocked.
- **Admin:** manage classes/teachers, assign and review work, review student activity, and use audit tools. Learning/exercise routes are hidden and blocked.

For backend configuration, start with [backend/SETUP.md](backend/SETUP.md). For changes to the project, see [CONTRIBUTING.md](CONTRIBUTING.md).
