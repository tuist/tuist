import assert from 'node:assert/strict';
import { test } from 'node:test';
import { changedLines, evidenceQuestions, evaluateEvidence } from './evidence.mjs';
import { summary } from './review.mjs';

const diff = 'diff --git a/old name.js b/new name.js\n--- a/old name.js\n+++ b/new name.js\n@@ -3,2 +4,3 @@\n context\n-old\n+new\n+extra\n@@ -20 +22 @@\n-previous\n+replacement\n';

test('maps additions and removals to real source lines across hunks and renamed files', () => {
  assert.deepEqual(changedLines(diff), [
    { file: 'old name.js', line: 4, side: 'base', source: 'old' },
    { file: 'new name.js', line: 5, side: 'head', source: 'new' },
    { file: 'new name.js', line: 6, side: 'head', source: 'extra' },
    { file: 'old name.js', line: 20, side: 'base', source: 'previous' },
    { file: 'new name.js', line: 22, side: 'head', source: 'replacement' },
  ]);
});

test('handles new, deleted, quoted paths and source lines that resemble headers', () => {
  const diff = 'diff --git a/new b/new\n--- /dev/null\n+++ "b/new\\tfile"\n@@ -0,0 +1,2 @@\n++++ payload\n+next\n' +
    'diff --git a/gone b/gone\n--- a/gone\n+++ /dev/null\n@@ -2 +0,0 @@\n-removed\n';
  assert.deepEqual(changedLines(diff), [
    { file: 'new\tfile', line: 1, side: 'head', source: '+++ payload' },
    { file: 'new\tfile', line: 2, side: 'head', source: 'next' },
    { file: 'gone', line: 2, side: 'base', source: 'removed' },
  ]);
});

test('covers every changed line within the 255-option limit and allows no finding', () => {
  const candidates = Array.from({ length: 600 }, (_, index) => ({ file: 'file.js', line: index + 1, side: 'head', source: 'text' }));
  const questions = evidenceQuestions(candidates);
  assert.equal(Object.keys(questions).length, 6);
  const allChoices = new Set();
  for (const question of Object.values(questions)) {
    assert.ok(Object.keys(question.criteria).length <= 255);
    assert.ok(Object.hasOwn(question.criteria, 'no_material_issue'));
    for (const key of Object.keys(question.criteria)) allChoices.add(key);
  }
  assert.equal(allChoices.size, 601);
  assert.deepEqual(evaluateEvidence({ answers: Object.fromEntries(Object.keys(questions).map((id) => [id, { type: 'choice', choice: 'no_material_issue', confidence: 0.9 }])) }, questions, candidates), []);
});

test('selected evidence uses local source, and invented or out-of-group locations fail', () => {
  const candidates = changedLines(diff);
  const questions = evidenceQuestions(candidates);
  const response = { answers: {
    maliciousBehavior_evidence_0: { type: 'choice', choice: 'line_1', confidence: 0.8 },
    promptInjection_evidence_0: { type: 'choice', choice: 'no_material_issue', confidence: 0.8 },
  } };
  assert.deepEqual(evaluateEvidence(response, questions, candidates), [{ check: 'Malicious behavior resistance', confidence: 0.8, ...candidates[1] }]);
  for (const choice of ['line_999', 'invented', '__proto__']) {
    response.answers.maliciousBehavior_evidence_0.choice = choice;
    assert.throws(() => evaluateEvidence(response, questions, candidates), /Invalid or missing/);
  }
  response.answers.maliciousBehavior_evidence_0.choice = 'line_1';
  for (const confidence of [NaN, -1, 2, '0.8']) {
    response.answers.maliciousBehavior_evidence_0.confidence = confidence;
    assert.throws(() => evaluateEvidence(response, questions, candidates));
  }
});

test('malformed and missing evidence responses cannot become clean reviews', () => {
  const candidates = changedLines(diff);
  assert.throws(() => evaluateEvidence({ answers: {} }, evidenceQuestions(candidates), candidates));
  assert.throws(() => changedLines('diff --git a/a b/a\n@@ invalid @@\n+line\n'));
});

test('evidence links target the correct commit and excerpts cannot inject markup', () => {
  const body = summary({ passed: true, threshold: 7, head: 'a'.repeat(40), base: 'b'.repeat(40), repository: 'tuist/tuist', ratings: [], findings: [
    { check: 'Prompt injection resistance', file: 'file [one].md', line: 2, side: 'base', confidence: 0.7, source: '</pre><img src=x> @someone' },
  ] });
  assert.match(body, new RegExp(`/blob/${'b'.repeat(40)}/file%20%5Bone%5D.md#L2`));
  assert.doesNotMatch(body, /<img|@someone/);
  assert.match(body, /removed line, 70% confidence/);
  assert.match(body, /not proof of malicious intent/);
});
