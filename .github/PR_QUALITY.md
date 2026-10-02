# Pull request quality review

The workflow in `workflows/pr-quality.yml` runs the standalone Node.js script in
`scripts/pr-quality/run.mjs`. It evaluates the complete text diff using Jev,
updates one GitHub comment, and retains a machine-readable report and Markdown
report for 14 days. No RawTree account, dashboard, or event storage is required.

## Enable

Store the key from the [TypeSafe console](https://console.typesafe.ai/keys)
in the `password` field of an item named `JEV_API_KEY` in the `tuist` 1Password
vault (`op://tuist/JEV_API_KEY/password`), then merge the script and workflow.
The workflow uses the existing `OP_SERVICE_ACCOUNT_TOKEN` repository secret
and resolves the Jev key with `op run`, following the status deployment pattern.
The service account must have read access to that item. A separate GitHub
secret for the Jev key is not needed. The workflow runs for opened, updated, reopened, edited, and ready
pull requests. Drafts and bot authors are skipped. Review failures fail the job;
low scores are advisory and do not fail it. Do not configure this workflow as a
required merge check while assessing the usefulness of its scores.

The script sends the title, description, complete three-dot text diff with 20
lines of context, and root `AGENTS.md` from the base commit to TypeSafe. It does
not execute contributor code. The workflow uses `pull_request_target`, checks
out trusted base code, installs only trusted dependencies with installation
scripts disabled, and fetches contributor commits solely to read the diff.
This also allows fork reviews. See the
[GitHub event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request_target).

## Run locally

Use Node.js 24, Git, and an authenticated
[GitHub command-line tool](https://cli.github.com/) from this repository's trusted
checkout. The `origin` remote must point to the repository being reviewed.
Provide `JEV_API_KEY` through your usual secret manager or environment.
To resolve it from 1Password, authenticate the installed 1Password command-line
tool and run:

```sh
JEV_API_KEY=op://tuist/JEV_API_KEY/password op run -- node .github/scripts/pr-quality/run.mjs 12345
```

```sh
npm ci --ignore-scripts --prefix .github/scripts/pr-quality
node .github/scripts/pr-quality/run.mjs 12345
```

This fetches commits without switching branches and writes `pr-quality.json` and
`pr-quality.md` in the current directory. Add `--post` to publish the comment.
The workflow updates its existing `github-actions[bot]` comment. Local runs
update the authenticated user's existing quality comment. Each publishing
identity keeps one comment per pull request, without modifying another
author's comments. Results use ✅ for passing scores, ⚠️ for scores below the
advisory threshold, and ➖ for unassessed dimensions. Use `JEV_MIN_SCORE` to override the advisory default
of 7 out of 10.

## Interpretation and limits

Jev evaluates 19 dimensions, including correctness, complexity, testability,
security, and performance. Each dimension includes applicability, score,
confidence, and a predefined weakness hint. These hints are not findings tied
to individual lines. A reviewer should investigate them rather than treat a
score as evidence of a defect. Scores use the mutable `jev-latest` model and
are not guaranteed to remain comparable across model updates.

The evaluator rejects text diffs over 1,000,000 bytes and combined descriptions
and guidance over 64,000 bytes rather than silently sampling. Binary changes
are listed as unassessed; binary-only changes cannot be scored. The evaluator
uses only root guidance, not nested repository guidance or unchanged source
files. For actionable line-specific findings, use a different reviewer that
returns and validates file locations and evidence.

Failed evaluations replace the comment with a fixed failure message. Run logs
never include provider error bodies. Before publishing, the script verifies
that the pull request is still open and its head, base, title, and description
match the reviewed input. Workflow concurrency cancels older runs.

## Validate

```sh
npm test --prefix .github/scripts/pr-quality
actionlint .github/workflows/pr-quality.yml
```

Live evaluation requires a TypeSafe key and sends source text to that service.
The automated tests exercise response validation and publication with simulated
provider responses and GitHub calls.

## Attribution

`review.mjs`, its tests, the dependency lock, and `metrics.json` were adapted from
[rawtreedb/jev-pr-quality](https://github.com/rawtreedb/jev-pr-quality/tree/c0a8d27cb61d183146e7e79534019a787d3498c5/scripts/jev-review)
at commit `c0a8d27cb61d183146e7e79534019a787d3498c5` under Apache License 2.0.
The rubric derives from Jev Review under the MIT License. Both license texts
are retained alongside the script.
