/* Source module: advanced-vocabulary-data.js
 * Starter B2-C2 vocabulary. Entries use the same schema as VOCAB.
 * CEFR labels are editorial estimates and should be reviewed before assessment use.
 */

const ADVANCED_VOCAB_TOPICS = [
  {
    name: "B2 — Argumentation and Society",
    level: "B2",
    words: [
      [3009, "die", "Auseinandersetzung", "debate / confrontation"],
      [3010, "der", "Zusammenhang", "connection / context"],
      [3011, "die", "Voraussetzung", "prerequisite / condition"],
      [3012, "die", "Auswirkung", "effect / impact"],
      [3013, "das", "Anliegen", "concern / request"],
      [3014, "-", "berücksichtigen", "to take into account"],
      [3015, "-", "sich auseinandersetzen mit", "to engage with / deal with"],
      [3016, "-", "gewährleisten", "to ensure / guarantee"],
      [3017, "-", "nachvollziehen", "to follow / understand"],
      [3018, "-", "in Anspruch nehmen", "to make use of"]
    ]
  },
  {
    name: "C1 — Academic and Professional Language",
    level: "C1",
    words: [
      [3019, "die", "Rahmenbedingung", "general condition / framework condition"],
      [3020, "das", "Vorhaben", "undertaking / planned project"],
      [3021, "die", "Tragweite", "scope / far-reaching significance"],
      [3022, "die", "Stellungnahme", "statement / position paper"],
      [3023, "der", "Sachverhalt", "facts of a case / state of affairs"],
      [3024, "-", "veranschaulichen", "to illustrate"],
      [3025, "-", "voraussetzen", "to presuppose / require"],
      [3026, "-", "einräumen", "to concede / admit"],
      [3027, "-", "beeinträchtigen", "to impair / adversely affect"],
      [3028, "-", "sich bewähren", "to prove effective / stand the test"]
    ]
  },
  {
    name: "C2 — Precision and Nuance",
    level: "C2",
    words: [
      [3029, "die", "Nuance", "nuance / subtle distinction"],
      [3030, "die", "Ambivalenz", "ambivalence"],
      [3031, "der", "Ermessensspielraum", "margin of discretion"],
      [3032, "die", "Tragfähigkeit", "viability / sustainability"],
      [3033, "die", "Kohärenz", "coherence"],
      [3034, "-", "präzisieren", "to make more precise"],
      [3035, "-", "relativieren", "to put into perspective / qualify"],
      [3036, "-", "konterkarieren", "to undermine / counteract"],
      [3037, "-", "abwägen", "to weigh up / consider carefully"],
      [3038, "-", "implizit", "implicit / implied"]
    ]
  }
];

ADVANCED_VOCAB_TOPICS.forEach(group => {
  TOPIC_NAMES.push(group.name);
  group.words.forEach(([n, art, de, en]) => {
    VOCAB.push({ n, art, de, en, topic: group.name, level: group.level });
  });
});
