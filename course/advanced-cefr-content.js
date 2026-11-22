/* Source module: advanced-cefr-content.js
 * Initial B2-C2 grammar expansion. Content is curated starter material, not an exhaustive syllabus.
 * Loaded after grammar-reference-data.js and grammar-expansion.js.
 */

GRAMMAR_DATA.push(
  {
    level: "B2",
    title: "Upper-intermediate",
    items: [
      {
        title: "Konjunktiv II Vergangenheit",
        explanation: "Use the past subjunctive for unreal or regretted situations in the past.",
        rule: "hätte / wäre + Partizip II\nWenn ich früher losgefahren wäre, hätte ich den Zug erreicht.\nWith modal verbs: hätte + infinitive + modal infinitive",
        examples: [
          ["Wenn ich mehr gelernt hätte, hätte ich die Prüfung bestanden.", "If I had studied more, I would have passed the exam."],
          ["Sie wäre gern mitgekommen, hatte aber keine Zeit.", "She would have liked to come along, but she had no time."],
          ["Du hättest mich anrufen können.", "You could have called me."]
        ],
        mistakes: [
          ["❌ Wenn ich hätte mehr gelernt ...", "✅ Wenn ich mehr gelernt hätte ..."],
          ["❌ Ich wäre die Aufgabe gemacht.", "✅ Ich hätte die Aufgabe gemacht."]
        ],
        exercise: { q: "Wenn er früher ___, ___ er den Zug erreicht.", options: ["losgefahren wäre / hätte", "losfahren würde / hat", "losgefahren hätte / wäre"], correct: 0, why: "Past unreal condition: wäre losgefahren; result: hätte erreicht." }
      },
      {
        title: "Vorgangspassiv und Zustandspassiv",
        explanation: "Vorgangspassiv focuses on an action or process; Zustandspassiv describes the resulting state.",
        rule: "Vorgangspassiv: werden + Partizip II\nZustandspassiv: sein + Partizip II\nDie Tür wird geöffnet. / Die Tür ist geöffnet.",
        examples: [
          ["Der Vertrag wird gerade geprüft.", "The contract is being checked."],
          ["Der Vertrag ist bereits unterschrieben.", "The contract is already signed."],
          ["Die Fenster wurden gestern gereinigt.", "The windows were cleaned yesterday."]
        ],
        mistakes: [
          ["❌ Die Tür ist gerade geöffnet (when describing the ongoing action).", "✅ Die Tür wird gerade geöffnet."],
          ["❌ Die Aufgabe ist gestern erledigt worden (when only the current state matters).", "✅ Die Aufgabe ist erledigt."]
        ],
        exercise: { q: "Choose the sentence that describes a present result.", options: ["Das Essen wird gekocht.", "Das Essen ist gekocht.", "Das Essen wurde gekocht."], correct: 1, why: "sein + Partizip II describes the resulting state." }
      },
      {
        title: "Relativsätze mit Präpositionen",
        explanation: "The preposition determines the case of the relative pronoun.",
        rule: "Preposition + relative pronoun + ... + finite verb at the end\nmit + Dativ: der Kollege, mit dem ...\nfür + Akkusativ: das Thema, für das ...",
        examples: [
          ["Das ist die Kollegin, mit der ich zusammenarbeite.", "That is the colleague with whom I work."],
          ["Der Bericht, auf den wir warten, kommt morgen.", "The report we are waiting for arrives tomorrow."],
          ["Das Thema, über das wir sprechen, ist wichtig.", "The topic we are discussing is important."]
        ],
        mistakes: [
          ["❌ Der Mann, mit den ich gesprochen habe ...", "✅ Der Mann, mit dem ich gesprochen habe ..."],
          ["❌ Das Thema, über dem wir sprechen ...", "✅ Das Thema, über das wir sprechen ..."]
        ],
        exercise: { q: "Das ist der Kunde, ___ wir gestern telefoniert haben.", options: ["mit dem", "mit den", "für den"], correct: 0, why: "telefonieren mit takes Dativ; Kunde is masculine singular." }
      },
      {
        title: "Präpositionen mit Genitiv",
        explanation: "Several formal and written prepositions govern the genitive case.",
        rule: "aufgrund + Genitiv\nangesichts + Genitiv\ntrotz + Genitiv (standard formal use)\nwährend + Genitiv\nInfolge des Unwetters fiel der Strom aus.",
        examples: [
          ["Aufgrund des Streiks fahren heute keine Züge.", "Due to the strike, no trains are running today."],
          ["Trotz der Schwierigkeiten haben wir das Ziel erreicht.", "Despite the difficulties, we achieved the goal."],
          ["Während des Gesprächs machte sie Notizen.", "She took notes during the conversation."]
        ],
        mistakes: [
          ["❌ Aufgrund dem Streik ...", "✅ Aufgrund des Streiks ..."],
          ["❌ Während den Gesprächen ...", "✅ Während der Gespräche ..."]
        ],
        exercise: { q: "___ des starken Regens blieb das Spiel unterbrochen.", options: ["Wegen", "Wegen dem", "Wegen den"], correct: 0, why: "wegen governs the genitive in standard formal German: wegen des Regens." }
      },
      {
        title: "Nominalisierung in formellen Texten",
        explanation: "Nominalisation turns actions or clauses into noun phrases and is common in reports and formal writing.",
        rule: "weil die Nachfrage gestiegen ist → wegen des Anstiegs der Nachfrage\nals die Sitzung begann → zu Beginn der Sitzung\nUse the correct case and article after the nominalised form.",
        examples: [
          ["Wegen der Verspätung verpassten wir den Anschluss.", "Because of the delay, we missed the connection."],
          ["Nach Abschluss der Untersuchung veröffentlichte das Team den Bericht.", "After completing the investigation, the team published the report."],
          ["Die Einführung der neuen Regelung erfolgt im Januar.", "The introduction of the new regulation takes place in January."]
        ],
        mistakes: [
          ["❌ Wegen der Nachfrage steigt ... (when a concise nominal phrase is intended).", "✅ Aufgrund des Anstiegs der Nachfrage ..."],
          ["❌ Nach die Untersuchung ...", "✅ Nach der Untersuchung ..."]
        ],
        exercise: { q: "Choose the correct nominal phrase: 'after the completion of the project'.", options: ["nach die Fertigstellung des Projekts", "nach Fertigstellung des Projekts", "nach dem fertigstellen des Projekts"], correct: 1, why: "nach governs Dativ; formal German often uses the noun without an article here." }
      }
    ]
  },
  {
    level: "C1",
    title: "Advanced",
    items: [
      {
        title: "Indirekte Rede mit Konjunktiv I",
        explanation: "Konjunktiv I marks reported speech and helps distinguish another person's statement from the writer's own position.",
        rule: "Er sagt: „Ich bin bereit.“ → Er sagt, er sei bereit.\nIf Konjunktiv I is identical to the indicative, Konjunktiv II is often used as a substitute.",
        examples: [
          ["Die Ministerin erklärte, die Gespräche seien noch nicht beendet.", "The minister explained that the talks were not yet over."],
          ["Der Zeuge sagte, er habe nichts gesehen.", "The witness said that he had seen nothing."],
          ["Sie behauptet, sie werde später zurückrufen.", "She claims that she will call back later."]
        ],
        mistakes: [
          ["❌ Er sagte, er ist bereit (in formal reported speech).", "✅ Er sagte, er sei bereit."],
          ["❌ Sie erklärte, sie haben keine Zeit (when the subject requires singular form).", "✅ Sie erklärte, sie habe keine Zeit."]
        ],
        exercise: { q: "Die Sprecherin erklärte, die Lage ___ stabil.", options: ["sei", "ist", "wäre gewesen"], correct: 0, why: "sein in Konjunktiv I, third-person singular: sei." }
      },
      {
        title: "Erweiterte Partizipialattribute",
        explanation: "A participial phrase can compress a relative clause and is especially common in formal and academic writing.",
        rule: "Relative clause: die Daten, die gestern veröffentlicht wurden\nParticiple attribute: die gestern veröffentlichten Daten\nThe participle agrees with the noun through an adjective ending.",
        examples: [
          ["Die gestern veröffentlichten Daten bestätigen den Trend.", "The data published yesterday confirm the trend."],
          ["Die im Labor getestete Substanz zeigte keine Nebenwirkungen.", "The substance tested in the laboratory showed no side effects."],
          ["Die von mehreren Instituten unterstützte Studie wurde vorgestellt.", "The study supported by several institutes was presented."]
        ],
        mistakes: [
          ["❌ die gestern veröffentlicht Daten", "✅ die gestern veröffentlichten Daten"],
          ["❌ das im Labor getesteten Material", "✅ das im Labor getestete Material"]
        ],
        exercise: { q: "Complete: 'die von der Jury ___ Entwürfe'.", options: ["ausgewählten", "ausgewählt", "auswählende"], correct: 0, why: "The participle functions as an adjective before a plural noun with a definite article: ausgewählten." }
      },
      {
        title: "Infinitivgruppen: um, ohne, statt ... zu",
        explanation: "These constructions express purpose, an accompanying absence, or an alternative action. The understood subject is usually the same as in the main clause.",
        rule: "um ... zu = in order to\nohne ... zu = without doing\nstatt / anstatt ... zu = instead of doing\nThe zu-infinitive goes at the end of the infinitive group.",
        examples: [
          ["Sie spart, um eine Weiterbildung zu finanzieren.", "She is saving in order to finance further training."],
          ["Er verließ den Raum, ohne sich zu verabschieden.", "He left the room without saying goodbye."],
          ["Statt sich zu beschweren, machte sie einen Vorschlag.", "Instead of complaining, she made a suggestion."]
        ],
        mistakes: [
          ["❌ Er ging, ohne zu sich verabschieden.", "✅ Er ging, ohne sich zu verabschieden."],
          ["❌ Ich lerne, um bestehe die Prüfung.", "✅ Ich lerne, um die Prüfung zu bestehen."]
        ],
        exercise: { q: "Sie nahm den Umweg, ___ den Stau zu vermeiden.", options: ["um", "ohne", "statt"], correct: 0, why: "um ... zu expresses the purpose of taking the detour." }
      },
      {
        title: "Funktionsverbgefüge",
        explanation: "A noun combines with a light verb to express a meaning that is often carried by a single verb in everyday language.",
        rule: "eine Entscheidung treffen = entscheiden\nKritik üben an + Dativ = kritisieren\nin Betracht ziehen = erwägen\nUse the complete expression as a vocabulary unit.",
        examples: [
          ["Der Ausschuss hat eine Entscheidung getroffen.", "The committee has made a decision."],
          ["Die Fachleute üben Kritik an dem Entwurf.", "The specialists criticise the draft."],
          ["Wir ziehen eine weitere Möglichkeit in Betracht.", "We are considering another possibility."]
        ],
        mistakes: [
          ["❌ eine Entscheidung machen", "✅ eine Entscheidung treffen"],
          ["❌ Kritik üben den Plan", "✅ Kritik an dem Plan üben"]
        ],
        exercise: { q: "Which phrase means 'to consider an option'?", options: ["eine Option in Betracht ziehen", "eine Option in die Betrachtung gehen", "eine Option Betrachtung machen"], correct: 0, why: "in Betracht ziehen is the established Funktionsverbgefüge." }
      },
      {
        title: "Satzklammer und Mittelfeld: Informationsstruktur",
        explanation: "German word order lets you place known or contrasting information early while keeping the finite verb in its required position.",
        rule: "Vorfeld | finite verb | Mittelfeld | verbal bracket\nDiesen Vorschlag | habe | ich gestern dem Team | geschickt.\nThe first position highlights the topic; it does not change the grammatical case.",
        examples: [
          ["Den Bericht hat die Abteilung bereits gestern veröffentlicht.", "The department already published the report yesterday."],
          ["Mit dieser Entscheidung muss sich der Vorstand noch beschäftigen.", "The board still has to deal with this decision."],
          ["Besonders wichtig ist dabei die langfristige Wirkung.", "The long-term effect is particularly important here."]
        ],
        mistakes: [
          ["❌ Diesen Vorschlag ich habe gestern geschickt.", "✅ Diesen Vorschlag habe ich gestern geschickt."],
          ["❌ Mit dieser Entscheidung der Vorstand muss sich beschäftigen.", "✅ Mit dieser Entscheidung muss sich der Vorstand beschäftigen."]
        ],
        exercise: { q: "Choose the correct sentence.", options: ["Diesen Punkt wir müssen noch klären.", "Diesen Punkt müssen wir noch klären.", "Diesen Punkt müssen noch wir klären."], correct: 1, why: "The finite verb remains in second position after the fronted object." }
      }
    ]
  },
  {
    level: "C2",
    title: "Mastery and nuance",
    items: [
      {
        title: "Modalpartikeln und Gesprächshaltung",
        explanation: "Modal particles such as doch, ja, eben, wohl and denn express stance, expectation and conversational nuance. Their effect depends on context and intonation.",
        rule: "Das weißt du doch. = shared knowledge / reminder\nDas ist ja interessant. = speaker's reaction\nWas machst du denn? = conversational question\nThere is rarely a one-word translation that works in every context.",
        examples: [
          ["Komm doch mit!", "Why don't you come along!"],
          ["Das hast du ja schon erklärt.", "You have already explained that, as we both know."],
          ["Wie konnte das denn passieren?", "How on earth could that happen?"]
        ],
        mistakes: [
          ["❌ Add a modal particle to every sentence as a direct translation of English emphasis.", "✅ Choose a particle only when its conversational meaning fits."],
          ["❌ Treat doch, ja and wohl as interchangeable.", "✅ Learn each particle in a complete dialogue and context."]
        ],
        exercise: { q: "A speaker reminds a friend of shared knowledge: 'Das weißt du ___.'", options: ["doch", "denn", "mal"], correct: 0, why: "doch can signal that the information should already be known to the listener." }
      },
      {
        title: "Konzessive und einschränkende Verknüpfungen",
        explanation: "Advanced connectors express contrast, limitation, concession and qualification more precisely than a simple aber.",
        rule: "wenngleich / obgleich = although (formal)\nzumal = especially since\ngeschweige denn = let alone\ninsofern, als = to the extent that",
        examples: [
          ["Wenngleich die Daten vorläufig sind, deuten sie auf einen klaren Trend hin.", "Although the data are preliminary, they indicate a clear trend."],
          ["Die Entscheidung ist nachvollziehbar, zumal die Kosten deutlich gesunken sind.", "The decision is understandable, especially since costs have fallen considerably."],
          ["Er kann kaum einen Satz erklären, geschweige denn einen Vortrag halten.", "He can barely explain a sentence, let alone give a presentation."]
        ],
        mistakes: [
          ["❌ Use geschweige denn as a synonym for weil.", "✅ Use it to add a stronger or less likely case after a negative or limiting statement."],
          ["❌ Wenngleich die Lage ist schwierig ...", "✅ Wenngleich die Lage schwierig ist ..."]
        ],
        exercise: { q: "Er kann kaum schwimmen, ___ einen Marathon im Wasser bewältigen.", options: ["geschweige denn", "zumal", "insofern"], correct: 0, why: "geschweige denn introduces an even less plausible or more demanding case." }
      },
      {
        title: "Register: verbal and nominal style",
        explanation: "Choose between verbal and nominal constructions according to audience, clarity and genre. Dense nominal style is common in formal reports but can reduce readability.",
        rule: "Verbal: Nachdem der Ausschuss den Bericht geprüft hatte, ...\nNominal: Nach Prüfung des Berichts durch den Ausschuss ...\nKeep the agent and the logical relation clear.",
        examples: [
          ["Nachdem die Kommission den Vorschlag geprüft hatte, veröffentlichte sie ihre Empfehlung.", "After the commission had reviewed the proposal, it published its recommendation."],
          ["Nach eingehender Prüfung des Vorschlags veröffentlichte die Kommission ihre Empfehlung.", "After a thorough review of the proposal, the commission published its recommendation."],
          ["Die Behörde setzte die Regelung aus, weil neue Hinweise vorlagen.", "The authority suspended the regulation because new information had emerged."]
        ],
        mistakes: [
          ["❌ Stack several abstract nouns when the actor or action becomes unclear.", "✅ Prefer a clear verbal clause when it improves readability."],
          ["❌ Assume nominal style is always more formal and therefore better.", "✅ Match sentence structure to the purpose and reader."]
        ],
        exercise: { q: "Which version is generally clearer for a broad audience?", options: ["Nach Durchführung einer Überprüfung erfolgte eine Anpassung.", "Nachdem das Team die Angaben geprüft hatte, passte es den Plan an."], correct: 1, why: "The verbal version names the actor and action directly." }
      },
      {
        title: "Fokus und Hervorhebung im Satz",
        explanation: "Fronting, contrastive stress and cleft-like constructions guide the reader toward the information that matters most.",
        rule: "Was ... betrifft, ... = as far as ... is concerned\nNicht X, sondern Y ... = not X but Y\nEntscheidend ist nicht die Menge, sondern die Qualität.",
        examples: [
          ["Was die Finanzierung betrifft, besteht noch Klärungsbedarf.", "As far as the financing is concerned, further clarification is needed."],
          ["Nicht die Dauer, sondern die Qualität der Ausbildung ist entscheidend.", "It is not the duration but the quality of the training that matters."],
          ["Besonders hervorzuheben ist die enge Zusammenarbeit der Teams.", "The close cooperation between the teams deserves particular emphasis."]
        ],
        mistakes: [
          ["❌ Use fronting without maintaining the finite verb's position.", "✅ Was die Finanzierung betrifft, besteht noch Klärungsbedarf."],
          ["❌ Repeat several emphasis structures in one paragraph.", "✅ Use one clear focus structure when it helps the argument."]
        ],
        exercise: { q: "Complete: 'Was die Qualität ___, sind weitere Tests nötig.'", options: ["betrifft", "betreffen", "betreffend"], correct: 0, why: "The fixed framing expression is 'Was ... betrifft'." }
      },
      {
        title: "Präzise Abstufung von Modalität",
        explanation: "At mastery level, choose modal and evidential forms to signal certainty, inference, obligation or distance without overstating a claim.",
        rule: "muss = strong necessity / strong inference in context\ndürfte = probable or expected\nsoll = reported claim / alleged information in some contexts\nkönnte = possibility\nscheint ... zu = appears to",
        examples: [
          ["Die Zahlen dürften im nächsten Quartal steigen.", "The figures are likely to rise next quarter."],
          ["Der Bericht soll bereits veröffentlicht worden sein.", "The report is said to have already been published."],
          ["Die Maßnahme scheint Wirkung zu zeigen.", "The measure appears to be having an effect."]
        ],
        mistakes: [
          ["❌ Present an inference with muss when the evidence only supports a possibility.", "✅ Match the modal form to the strength of the evidence."],
          ["❌ Treat soll as a neutral future marker in every context.", "✅ In report style, soll can mark information attributed to another source."]
        ],
        exercise: { q: "Which form expresses a cautious probability?", options: ["dürfte", "muss", "hat"], correct: 0, why: "dürfte often expresses a likely but not certain expectation." }
      }
    ]
  }
);
