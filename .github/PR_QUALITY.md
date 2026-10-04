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
and resolves the Jev key with `op read` in a dedicated step, so the evaluator
step never receives the service-account token.
The service account must have read access to that item. A separate GitHub
secret for the Jev key is not needed. The workflow runs for opened, updated, reopened, edited, and ready
pull requests. Drafts and bot authors are skipped. Review failures fail the job;
low scores are advisory and do not fail it. Do not configure this workflow as a
required merge check while assessing the usefulness of its scores.

The script sends the title, description, complete three-dot text diff with 20
lines of context, and root `AGENTS.md` from the base commit to TypeSafe, through
Atlas when configured. It does
not execute contributor code. The workflow uses `pull_request_target`, checks
out trusted base code, installs only trusted dependencies with installation
scripts disabled, and fetches contributor commits solely to read the diff.
This also allows fork reviews. See the
[GitHub event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request_target).

## Route through Atlas

Create a provider in Atlas with endpoint `https://api.typesafe.ai/v1`, decision
path `systemone`, a timeout of 45,000 milliseconds, and its TypeSafe credential. Create a profile targeting
`jev-latest` and configure its input and output prices. TypeSafe's published
Jev rate is $0.042 per million input tokens with free output; check the
[current provider pricing](https://docs.typesafe.ai/models) when configuring it.
Create a dedicated profile token for the review workflow.

Set repository variables `PR_QUALITY_INFERENCE_BASE_URL` to
`https://atlas.tuist.dev/inference` and `PR_QUALITY_INFERENCE_MODEL` to that
profile's name, and the repository secret `PR_QUALITY_INFERENCE_TOKEN` to its
token. The client adds `/v1/systemone` to the base. Atlas keeps the TypeSafe
credential and records token counts and configured costs for every quality
and evidence request. The evaluator only receives its restricted profile token.
If the relay is configured but its token or profile name is missing, the workflow fails rather
than sending source text directly to TypeSafe.

For local runs, set `JEV_BASE_URL`, `JEV_MODEL`, and `JEV_API_KEY` to the relay
base, profile name, and profile token. Omitting these overrides preserves direct
TypeSafe calls. The evaluator consumes Jev's native question and answer format;
other decision providers need a compatible contract or a separate adapter. Automatic retries
are disabled on both sides of the relay so an ambiguous timeout cannot duplicate
a paid decision call. The evaluator allows 60 seconds per call; keep the provider
timeout below that budget. Costs reflect provider-reported usage. Missing or invalid
usage on a successful decision response produces a warning and an audit flag
(`usage_reported: false`), so zero recorded tokens do not imply a free request.

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

Jev evaluates 21 dimensions, including correctness, complexity, testability,
security, and performance. Each dimension includes applicability, score,
confidence, and a predefined weakness hint. The general quality hints are not findings tied
to individual lines. The focused malicious-behavior and prompt-injection checks
also select candidate evidence from changed lines, with commit-specific source
links, source excerpts, and confidence. A reviewer should investigate them rather than treat a
score as evidence of a defect. Direct calls default to the mutable `jev-latest`
model; relay calls use the model configured on the Atlas profile. Scores are not
guaranteed to remain comparable across model updates.

The evaluator rejects text diffs over 1,000,000 bytes and combined descriptions
and guidance over 64,000 bytes rather than silently sampling. Binary changes
are listed as unassessed; binary-only changes cannot be scored. The evaluator
uses only root guidance, not nested repository guidance or unchanged source
files. Both focused ratings are part of the quality request. When a focused rating
selects a weakness or falls below the threshold, a separate Jev choice request
for that check selects source evidence from the complete text diff. This avoids
combining all quality questions and evidence options into one oversized request. Each group contains at most 254 changed lines plus a
no-issue option, within Jev's 255-option limit. The complete diff is annotated with changed-line identifiers, so choice
options reference evidence without duplicating source text. Every added and
removed text line is considered, and a group can select at most one candidate per focused
check. Locations and excerpts come from the local diff, so Jev cannot invent
a file or line. Removed lines link to the base commit. Focused hints without selected source evidence are omitted. Missing or invalid
evidence answers fail the review rather than appearing as a clean result.

The focused questions cover credential theft, unexpected transmission of
sensitive data, hidden execution, privileged workflow or installation behavior,
and attempts to manipulate reviewers or model tools through untrusted text.
They distinguish these from legitimate security tests, documentation, and
quoted attack examples. Selected lines remain candidates for human
investigation, not proof of a malicious author. No selected lines does not
establish safety. Extra evidence choices consume tokens; provider input
limits can reject a large request rather than returning a partial review.
Contributor instructions in the title or description can affect the focused
ratings, but source evidence is limited to changed code and documentation.

Failed evaluations replace the comment with a failure message built from
allowlisted diagnostic codes and validated HTTP status numbers. The artifact
`pr-quality-error.json` records those diagnostics, while `pr-quality.json`
remains null when no scores are available. Provider input-limit failures are
identified explicitly; arbitrary exception messages, credentials, submitted
source text, and provider error bodies are never copied into diagnostics. Before publishing, the script verifies
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
