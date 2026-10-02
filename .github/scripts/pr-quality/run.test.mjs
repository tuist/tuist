import assert from 'node:assert/strict';
import { test } from 'node:test';
import { formatComment, marker, runReview } from './run.mjs';

const pr = { number: 12, state: 'open', title: 'Change', body: null, head: { sha: 'a'.repeat(40) }, base: { sha: 'b'.repeat(40) } };
const report = { passed: false, threshold: 7, batches: [{ batch: 1, ratings: [{ key: 'correctness', label: 'Correctness', applicable: true, score: 6, confidence: 0.9, passed: false, hint: 'An edge case is missing.' }] }] };

function fixture(overrides = {}) {
  const calls = [];
  return {
    calls,
    options: {
      pr, post: true,
      git: (...args) => { calls.push(args); return args[0] === 'show' ? 'Trusted guidance' : 'diff --git a/a b/a\n'; },
      evaluate: async (input) => { calls.push(input); return structuredClone(report); },
      api: async (path, options) => {
        calls.push({ path, options });
        if (path.startsWith('pulls/')) return pr;
        if (options?.paginate) return [];
        return {};
      },
      ...overrides,
    },
  };
}

test('publishes below-threshold scores without failing the advisory workflow', async () => {
  const { calls, options } = fixture();
  assert.deepEqual(await runReview(options), { failed: false, published: true });
  assert.equal(calls.at(-1).options.method, 'POST');
  assert.match(calls.at(-1).options.body.body, /Below the advisory threshold/);
  assert.ok(calls.some((call) => call.repositoryContext === 'Trusted guidance'));
  assert.ok(calls.some((call) => Array.isArray(call) && call.includes('--no-ext-diff') && call.includes('--no-textconv')));
});

test('does not publish when head, base, metadata, or open state changed', async () => {
  for (const changed of [{ head: { sha: 'c'.repeat(40) } }, { base: { sha: 'c'.repeat(40) } }, { title: 'New title' }, { body: 'New description' }, { state: 'closed' }]) {
    const { options } = fixture({ api: async (_path, settings) => { assert.equal(settings, undefined); return { ...pr, ...changed }; } });
    assert.equal((await runReview(options)).published, false);
  }
});

test('updates only its bot-owned comment, including on later pages', async () => {
  const { options } = fixture();
  options.api = async (path, settings) => {
    if (path.startsWith('pulls/')) return pr;
    if (settings?.paginate) return [
      { id: 1, user: { login: 'contributor', type: 'User' }, body: marker },
      { id: 2, user: { login: 'github-actions[bot]', type: 'Bot' }, body: marker },
    ];
    assert.equal(path, 'issues/comments/2');
    assert.equal(settings.method, 'PATCH');
  };
  await runReview(options);
});

test('provider failure replaces old scores without exposing error text', async () => {
  let saved;
  const { calls, options } = fixture({ evaluate: async () => { throw new Error('secret-source-text'); }, save: (value) => { saved = value; } });
  assert.equal((await runReview(options)).failed, true);
  assert.equal(saved.report, undefined);
  assert.match(saved.body, /could not complete/);
  assert.doesNotMatch(calls.at(-1).options.body.body, /secret-source-text/);
});

test('local report mode does not contact GitHub to publish', async () => {
  const { options } = fixture({ post: false, api: () => assert.fail('unexpected GitHub call') });
  assert.equal((await runReview(options)).published, false);
});

test('rejects invalid identifiers before fetching or evaluating', async () => {
  const { calls, options } = fixture({ pr: { ...pr, head: { sha: '--malicious' } } });
  await assert.rejects(runReview(options), /valid commit identifiers/);
  assert.equal(calls.length, 0);
});

test('comment contains no em dashes and makes advisory limitations explicit', () => {
  const body = formatComment(report, pr);
  assert.doesNotMatch(body, /—/);
  assert.match(body, /advisory model judgments/);
});

test('binary filenames cannot inject markup or mentions into the comment', () => {
  const body = formatComment({ ...report, unassessedBinaryFiles: ['`<img>\n|@someone'] }, pr);
  assert.doesNotMatch(body, /<img>/);
  assert.match(body, /&#96;/);
});
