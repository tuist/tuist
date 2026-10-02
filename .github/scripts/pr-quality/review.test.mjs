import assert from 'node:assert/strict';
import test from 'node:test';
import { separateBinaryChanges, validateDiff, buildQuestions, evaluateResponse, parseThreshold, review, summary } from './review.mjs';

function response(score = 6) {
  return { answers: Object.fromEntries(Object.entries(buildQuestions()).map(([id, question]) => [id,
    question.type === 'noul' ? { type: 'noul', noul: 0.9 }
      : question.type === 'score' ? { type: 'score', score, confidence: 0.8 }
        : { type: 'choice', choice: 'no_material_issue', confidence: 0.8 },
  ])) };
}
const diff = 'diff --git a/a.js b/a.js\n--- a/a.js\n+++ b/a.js\n@@ -1 +1 @@\n-old\n+new\n';

test('preserves all 19 dimensions and the ten-level scoring rubric', () => {
  const questions = buildQuestions();
  assert.equal(Object.keys(questions).length, 57);
  assert.equal(questions.correctness_score.criteria.length, 10);
  assert.equal(evaluateResponse(response(), 7).ratings.length, 19);
});

test('threshold accepts only finite values from 1 to 10', () => {
  for (const invalid of ['', ' ', '0', '11', 'NaN', 'Infinity', '7oops', undefined]) {
    assert.throws(() => parseThreshold(invalid));
  }
  assert.equal(parseThreshold('7.5'), 7.5);
});

test('normalizes zero-based scores and gates every dimension before rounding', () => {
  assert.equal(evaluateResponse(response(6), 7).passed, true);
  assert.equal(evaluateResponse(response(5.999), 7).passed, false);
  const data = response(9);
  data.answers.security_score.score = 0;
  const result = evaluateResponse(data, 7);
  assert.equal(result.passed, false);
  assert.equal(result.ratings.find((rating) => rating.key === 'security').score, 1);
});

test('inapplicable dimensions do not block but an empty assessment fails', () => {
  const data = response(6);
  data.answers.performance_applicable.noul = 0.49;
  data.answers.performance_score.score = 0;
  assert.equal(evaluateResponse(data, 7).passed, true);
  for (const answer of Object.values(data.answers)) {
    if (answer.type === 'noul') answer.noul = 0;
  }
  assert.throws(() => evaluateResponse(data, 7), /could not assess/);
});

test('fails closed on missing, non-finite, out-of-range, or unknown decisions', () => {
  for (const invalid of [null, {}, { answers: {} }]) assert.throws(() => evaluateResponse(invalid, 7));
  for (const score of [NaN, Infinity, -1, 10, '7']) {
    assert.throws(() => evaluateResponse(response(score), 7));
  }
  const data = response();
  data.answers.security_weakness.choice = 'invented_choice';
  assert.throws(() => evaluateResponse(data, 7));
});

const binaryDiff = 'diff --git a/app/favicon.ico b/app/favicon.ico\nindex 1..2 100644\nBinary files a/app/favicon.ico and b/app/favicon.ico differ\n';

test('rejects empty, unseparated binary, and oversized diffs', () => {
  assert.doesNotThrow(() => validateDiff(diff));
  assert.throws(() => validateDiff(''));
  assert.throws(() => validateDiff(diff + 'x'.repeat(1_000_000)), /1 MB/);
  assert.throws(() => validateDiff('diff --git a/a b/a\nGIT binary patch\n'), /Binary/);
});

test('separates binary files from the reviewable text diff', () => {
  assert.deepEqual(separateBinaryChanges(diff + binaryDiff), { diff, binaryFiles: ['app/favicon.ico'] });
  assert.deepEqual(separateBinaryChanges(diff), { diff, binaryFiles: [] });
  assert.throws(() => separateBinaryChanges(binaryDiff), /only changes binary files/);
});

test('reviews text changes and reports binary files as unassessed', async () => {
  const report = await review({
    diff: binaryDiff + diff, task: '', repositoryContext: '', threshold: 7, apiKey: 'test-placeholder',
    fetch: async (_url, options) => {
      const { state } = JSON.parse(options.body);
      assert.equal(state.diff, diff);
      assert.match(state.repositoryContext, /not assessed:\n- app\/favicon.ico/);
      return Response.json(response(6));
    },
  });
  assert.equal(report.passed, true);
  assert.deepEqual(report.unassessedBinaryFiles, ['app/favicon.ico']);
  assert.match(summary({ ...report, head: 'a'.repeat(40), base: 'b'.repeat(40) }), /Binary files not assessed/);
});

test('SDK sends authenticated typed questions to the fixed API and returns gate failure', async () => {
  let calls = 0;
  const report = await review({
    diff, task: 'Change behavior', repositoryContext: 'Project conventions', threshold: 7,
    apiKey: 'test-placeholder',
    fetch: async (url, options) => {
      calls++;
      assert.equal(String(url), 'https://api.typesafe.ai/v1/systemone');
      assert.equal(new Headers(options.headers).get('authorization'), 'Bearer test-placeholder');
      const request = JSON.parse(options.body);
      assert.equal(request.state.diff, diff);
      assert.equal(request.model, 'jev-latest');
      assert.equal(Object.keys(request.questions).length, 57);
      return Response.json(response(5));
    },
  });
  assert.equal(calls, 1);
  assert.equal(report.passed, false);
  const markdown = summary({ ...report, head: 'a'.repeat(40), base: 'b'.repeat(40) });
  assert.match(markdown, /⚠️ Below threshold/);
  assert.match(markdown, /Security/);
  assert.match(markdown, /6.00/);
});

test('missing key makes no request; API failures never leak response bodies', async () => {
  const input = { diff, task: '', repositoryContext: '', threshold: 7 };
  await assert.rejects(review(input), /JEV_API_KEY is missing/);
  await assert.rejects(review({ ...input, apiKey: 'test-placeholder', fetch: async () =>
    Response.json({ detail: 'private server response' }, { status: 401 }),
  }), (error) => /HTTP 401/.test(error.message) && !error.message.includes('private'));
});

test('sends implementations and tests over the old 48 KB boundary in one complete request', async () => {
  const implementation = diff + ' context\n'.repeat(5500);
  const tests = diff.replaceAll('a.js', 'a.test.js');
  const completeDiff = implementation + tests;
  let calls = 0;
  const result = await review({
    diff: completeDiff, task: '', repositoryContext: '', threshold: 7, apiKey: 'test-placeholder',
    fetch: async (_url, options) => {
      calls++;
      assert.equal(JSON.parse(options.body).state.diff, completeDiff);
      // A weak dimension still fails the complete review.
      return Response.json(response(5));
    },
  });
  assert.equal(calls, 1);
  assert.equal(result.ratings.length, 19);
  assert.equal(result.passed, false);
});

test('provider input limits fail closed without splitting or leaking error bodies', async () => {
  let calls = 0;
  await assert.rejects(review({
    diff, task: '', repositoryContext: '', threshold: 7, apiKey: 'test-placeholder',
    fetch: async () => {
      calls++;
      return Response.json({ detail: { error_type: 'max_tokens_exceeded', message: 'private context' } }, { status: 400 });
    },
  }), (error) => /Split the PR into smaller coherent changes/.test(error.message) && !error.message.includes('private'));
  assert.equal(calls, 1);
});
