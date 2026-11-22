# A1-C2 expansion: product and content plan

This branch extends the existing Sprachtreppe A1-B1 course. It is deliberately additive: the original offline course, Android shell, and Supabase LMS remain in place.

## What this branch adds

- B2, C1 and C2 grammar sections with explanations, rules, model sentences, common errors and a short check question.
- Six-level filtering for grammar and vocabulary (A1, A2, B1, B2, C1, C2).
- A small advanced vocabulary seed set to validate the data format and learning flow.
- A content expansion plan for the full curriculum, lexicon, TTS and teacher tools.

The B2-C2 lesson set is a starter tranche. It is not yet an exhaustive CEFR syllabus, dictionary or exam-preparation catalogue. Each item should be reviewed by a qualified German teacher before it is used for formal assessment.

## Platform modules

| Area | Student experience | Teacher experience |
|---|---|---|
| Curriculum | A1-C2 level map, lessons and checkpoints | Assign level, lesson and due date |
| Grammar | Clear explanation, contrast, examples, mistake notes and practice | Assign topics; inspect accuracy and recurring errors |
| Vocabulary | Search, article/plural, word forms, examples, audio and SRS | Assign vocabulary sets and mastery targets |
| Verbs | Conjugation, separable/reflexive use, auxiliary, Partizip II and prepositions | Target weak verb families |
| Reading | Levelled text, glossary and comprehension tasks | Set texts and review responses |
| Listening | Native-speaker recordings, replay controls and comprehension | Set listening tasks and review scores |
| Writing | Sentence, email, paragraph and essay prompts with revision history | Rubric, inline comments and grades |
| Speaking | Guided prompts, pronunciation practice and optional recording | Assign speaking prompts and review submissions |
| Practice | Parameterised grammar, vocabulary, sentence, paragraph and error-correction tasks | Assign a practice profile and inspect attempts |
| Dictionary | Searchable lexicon and word relationships | Curate, approve and publish vocabulary |

## Dictionary data model

A complete inventory of every German word is not a realistic finite hand-curated list. German compounds, regional forms, inflections, technical terms and new words keep expanding. Build a broad, source-attributed lexicon that can be imported and updated.

Recommended fields:

- lemma, display form, part of speech and CEFR estimate;
- noun gender, plural and genitive form where relevant;
- verb principal parts, auxiliary, separability, reflexivity and governed prepositions;
- English (and optional Gujarati) meanings, usage labels and register;
- example sentences, collocations, synonyms, antonyms and word family;
- audio reference, source, licence, attribution and editorial-review state.

Do not scrape or redistribute copyrighted dictionary entries. Use datasets whose licence explicitly permits the intended use, record provenance, and keep source-specific attribution.

## Native audio strategy

The current app uses browser speech synthesis with a German voice when the device provides one. That is useful for offline fallback, but voice quality and availability vary by browser and operating system. For consistent native-quality audio:

1. Select a German (Germany) neural TTS provider or commission speaker recordings.
2. Generate audio on a trusted server or Supabase Edge Function; keep provider credentials server-side.
3. Store generated clips in Supabase Storage with word/phrase IDs and cache headers.
4. Retain browser speech synthesis as a no-cost fallback and allow the learner to change speech rate.
5. Use real licensed speaker recordings for listening examinations where assessment requires natural speech rather than TTS.

## Infinite practice design

"Infinite" means parameterised generation, not unconstrained random text. Generate from validated grammar frames, verb valency, case requirements, noun gender, tense, CEFR vocabulary and discourse goals. Each generated item should carry:

- stable exercise ID and generator version;
- target level, skill and grammar tags;
- correct answer or accepted-answer set;
- explanation and source rule;
- difficulty estimate and validation state.

Do not generate arbitrary word combinations. A sentence must pass agreement, case, verb-position and semantic-plausibility checks before it reaches the learner. Writing and speaking outputs need rubric-based or teacher review rather than pretending that one exact string is the only valid answer.

## Roles and database

Keep Supabase Auth as the only credential system. The existing app has student, teacher and admin roles, approval, teacher-to-student/class relationships, class invites, assignments, submissions, notifications and progress tracking. Roles must be granted by trusted admin-side functions; never trust a role sent by the client or stored in editable user metadata.

Recommended additional content tables, introduced through reviewed migrations rather than ad-hoc production SQL:

- cefr_levels, lessons, grammar_topics, lesson_prerequisites;
- lexicon_entries, lexicon_senses, lexicon_forms, lexicon_examples, lexicon_relations;
- audio_assets, reading_passages, listening_items, writing_prompts;
- exercise_templates, exercise_attempts, writing_submissions, teacher_feedback;
- content_sources, content_reviews, content_versions.

Public curriculum content can be readable by signed-in learners. Student attempts and submissions must remain user-scoped; teachers may see only students/classes assigned to them; admin-only content curation needs explicit policies. Enable and test RLS on every exposed table.

## Delivery phases

1. **Foundation (this branch):** six-level navigation, seed B2-C2 grammar and vocabulary, documentation, preserve the current LMS.
2. **Curriculum:** audited A1-C2 grammar map, lesson plans, reading/listening/writing/speaking syllabi and CEFR checkpoints.
3. **Lexicon:** licensed corpus import, noun/verb morphology, duplicate handling, source attribution and search indexing.
4. **Practice engine:** tested grammar-aware generators, accepted-answer rules, sentence quality checks and adaptive review.
5. **Audio:** voice-provider integration, clip caching, licensed recordings and pronunciation controls.
6. **Teacher tools:** assignment builder, class analytics, writing rubric, feedback, exportable reports and moderation.
7. **Release:** desktop/mobile responsive testing, offline/online sync tests, accessibility, security review, backups and release automation.

## Safety and release checklist

- Never commit Supabase service-role keys, TTS API secrets, teacher passwords or student credentials.
- Use Supabase publishable/anon key only in the browser/Android client and rely on RLS.
- Create teacher accounts through admin promotion/invitation; do not ship shared "teacher" and "student" passwords.
- Test with one admin, one teacher, two students and separate browser/device sessions.
- Test assignment visibility, teacher isolation, student data isolation, offline retries and duplicate submission handling.
- Run the existing build and test workflow before merging this branch to main.
