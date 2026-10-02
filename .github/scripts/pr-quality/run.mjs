import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { parseThreshold, review, summary } from './review.mjs';

export const marker = '<!-- tuist-pr-quality -->';

export function formatComment(report, pr, runUrl) {
  const details = report ? summary(report)
    : `## Pull request quality\n\n⚠️ The review could not complete. No scores are available.\n\nReviewed commit: \`${pr.head.sha}\`.`;
  return `${marker}\n${details}${runUrl ? `\n\n[Workflow logs and report](${runUrl})` : ''}`;
}

export async function runReview({ pr, git, api, evaluate = review, apiKey, threshold = 7, post = false, commentAuthor = 'github-actions[bot]', runUrl, save = () => {} }) {
  if (!Number.isSafeInteger(pr.number) || pr.number < 1 || !/^[a-f0-9]{40}$/.test(pr.base?.sha) || !/^[a-f0-9]{40}$/.test(pr.head?.sha)) {
    throw new Error('Expected a pull request with valid commit identifiers.');
  }
  git('fetch', '--no-tags', 'origin', pr.base.sha, `refs/pull/${pr.number}/head`);
  const diff = git('diff', '--no-ext-diff', '--no-textconv', '--find-renames', '--unified=20', `${pr.base.sha}...${pr.head.sha}`, '--');
  let repositoryContext = 'No root AGENTS.md found.';
  try { repositoryContext = git('show', `${pr.base.sha}:AGENTS.md`); } catch { /* Guidance is optional. */ }
  let report;
  try {
    report = await evaluate({ diff, task: `${pr.title ?? ''}\n\n${pr.body ?? ''}`, repositoryContext, threshold, apiKey });
    report.head = pr.head.sha;
    report.base = pr.base.sha;
  } catch {
    // Provider failures can echo source text or credentials. Publish a fixed message.
  }
  const body = formatComment(report, pr, runUrl);
  save({ report, body });
  if (post) {
    const current = await api(`pulls/${pr.number}`);
    if (current.state !== 'open' || current.head.sha !== pr.head.sha || current.base.sha !== pr.base.sha || current.title !== pr.title || current.body !== pr.body) {
      return { failed: !report, published: false };
    }
    const comments = await api(`issues/${pr.number}/comments`, { paginate: true });
    const existing = comments.find((comment) => comment.user?.login === commentAuthor && comment.body?.startsWith(marker));
    await api(existing ? `issues/comments/${existing.id}` : `issues/${pr.number}/comments`, {
      method: existing ? 'PATCH' : 'POST', body: { body },
    });
  }
  return { failed: !report, published: post };
}

async function main() {
  const args = process.argv.slice(2);
  const post = args.includes('--post');
  const number = args.find((arg) => arg !== '--post');
  const event = process.env.GITHUB_EVENT_PATH ? JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : null;
  if (args.some((arg) => arg !== '--post' && arg !== number) || (!event && !/^\d+$/.test(number ?? ''))) {
    throw new Error('Usage: node .github/scripts/pr-quality/run.mjs <pull-request-number> [--post]');
  }
  const exec = (command, args, options = {}) => execFileSync(command, args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'], ...options });
  const repository = process.env.GITHUB_REPOSITORY ?? exec('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']).trim();
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Invalid repository.');
  const api = async (path, { method = 'GET', body, paginate = false } = {}) => {
    const args = ['api', `repos/${repository}/${path}`, '--method', method];
    if (paginate) args.push('--paginate', '--slurp');
    if (body) args.push('--input', '-');
    const result = JSON.parse(exec('gh', args, body ? { input: JSON.stringify(body) } : {}));
    return paginate ? result.flat() : result;
  };
  const pr = event?.pull_request ?? await api(`pulls/${number}`);
  if (!process.env.JEV_API_KEY?.trim()) throw new Error('Configure JEV_API_KEY before running the review.');
  const result = await runReview({
    pr, api, commentAuthor: event ? 'github-actions[bot]' : exec('gh', ['api', 'user', '--jq', '.login']).trim(), git: (...args) => exec('git', args), apiKey: process.env.JEV_API_KEY,
    threshold: parseThreshold(process.env.JEV_MIN_SCORE ?? '7'), post,
    runUrl: process.env.GITHUB_RUN_ID ? `https://github.com/${repository}/actions/runs/${process.env.GITHUB_RUN_ID}` : undefined,
    save: ({ report, body }) => {
      // Always replace the report, including failed runs, so reruns cannot reuse stale scores.
      writeFileSync('pr-quality.json', JSON.stringify(report ?? null, null, 2) + '\n');
      writeFileSync('pr-quality.md', body + '\n');
      if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, body + '\n');
      console.log(body);
    },
  });
  if (result.failed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    console.error('Pull request quality review failed. Check authentication, configuration, diff size, and service availability.');
    process.exitCode = 1;
  });
}
