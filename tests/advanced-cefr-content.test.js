const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const load = (file, context) => {
  vm.runInNewContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
};

test('B2, C1 and C2 grammar lessons have complete exercise data', () => {
  const context = { GRAMMAR_DATA: [], GRAMMAR_GUIDE: {} };
  load('course/advanced-cefr-content.js', context);
  const levels = new Set(context.GRAMMAR_DATA.map(section => section.level));
  assert.deepEqual([...levels].sort(), ['B2', 'C1', 'C2']);
  for (const section of context.GRAMMAR_DATA) {
    assert.ok(section.items.length >= 5, section.level + ' should have a starter set of topics');
    for (const item of section.items) {
      assert.ok(item.title && item.explanation && item.rule, section.level + ' topic has its teaching fields');
      assert.ok(Array.isArray(item.examples) && item.examples.length >= 2);
      assert.ok(Array.isArray(item.mistakes) && item.mistakes.length >= 1);
      assert.ok(Array.isArray(item.exercise.options) && item.exercise.options.length >= 2);
      assert.ok(item.exercise.correct >= 0 && item.exercise.correct < item.exercise.options.length);
    }
  }
});

test('advanced vocabulary uses unique IDs and valid CEFR tags', () => {
  const context = { TOPIC_NAMES: [], VOCAB: [] };
  load('course/advanced-vocabulary-data.js', context);
  assert.equal(context.VOCAB.length, 30);
  assert.equal(new Set(context.VOCAB.map(word => word.n)).size, context.VOCAB.length);
  assert.deepEqual([...new Set(context.VOCAB.map(word => word.level))].sort(), ['B2', 'C1', 'C2']);
  assert.equal(context.TOPIC_NAMES.length, 3);
});

test('course build includes the advanced data after its base data', () => {
  const builder = fs.readFileSync(path.join(root, 'scripts/build-course.py'), 'utf8');
  assert.ok(builder.indexOf("'vocabulary-data.js'") < builder.indexOf("'advanced-vocabulary-data.js'"));
  assert.ok(builder.indexOf("'grammar-expansion.js'") < builder.indexOf("'advanced-cefr-content.js'"));
});
