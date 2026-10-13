import '../models/course_module.dart';

class CourseService {
  const CourseService();

  List<CourseModule> get modules => const [
        CourseModule(
          id: 'a1-foundations',
          level: 'A1',
          title: 'Build the foundations',
          description: 'Build clear everyday German sentences and control the basic cases.',
          topics: [
            'sein and haben',
            'Personal pronouns and verb endings',
            'Articles and nominative',
            'Accusative',
            'First dative patterns',
            'Modal verbs',
            'Separable verbs',
            'nicht vs. kein',
            'Questions and word order',
            'Imperative',
            'Perfekt',
          ],
        ),
        CourseModule(
          id: 'a2-connections',
          level: 'A2',
          title: 'Join ideas and describe experiences',
          description: 'Connect ideas, control cases and handle common A2 sentence patterns.',
          topics: [
            'weil and dass',
            'wenn vs. als',
            'Indirect questions: ob and W-words',
            'deshalb and trotzdem',
            'Modal verbs in Präteritum',
            'Konjunktiv II requests',
            'Adjective endings',
            'Reflexive verbs',
            'Comparison',
            'Two-way prepositions',
            'Verb-preposition pairs',
            'Infinitive clauses with zu',
          ],
        ),
        CourseModule(
          id: 'b1-clear-expression',
          level: 'B1',
          title: 'Explain, compare and argue clearly',
          description: 'Build longer explanations, organise writing and express relationships precisely.',
          topics: [
            'Plusquamperfekt',
            'Past Konjunktiv II',
            'Passive with modal verbs',
            'Indirect speech',
            'Genitive',
            'N-declension',
            'Relative clauses with prepositions',
            'Two-part connectors',
            'Purpose clauses',
            'Futur I assumptions',
            'Participles as adjectives',
            'Process vs. resulting state',
          ],
        ),
      ];
}
