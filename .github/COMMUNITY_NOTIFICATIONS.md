# Community notifications

`workflows/community-notifications.yml` posts newly opened issues and pull
requests in `tuist/tuist` to `#support` in the Tuist Company Slack workspace
through the existing GitHub Notifications app's incoming webhook.
Draft PRs are included. Edits, pushes, comments, reopening, and marking a PR ready
do not send another notification. This is an intake feed; GitHub remains the
place to assign, review, and close work. It does not backfill existing items.

## Author filtering

The workflow checks the issue/PR author, not the event sender. It excludes:

- GitHub accounts of type `Bot` and logins ending in `[bot]`.
- `tuistit`, the legacy automation account that has a human account type.
- Members of `@tuist/company` (employees) or `@tuist/external` (contractors).

Team membership is fetched with pagination for each event. Keep those teams up
to date during onboarding/offboarding. Update `botLogins` in
`scripts/community-notifications.cjs` when adding automation that uses a normal
GitHub account. Repository association and write access are deliberately not
used as employment signals: community contributors can have either.

A missing token, inaccessible team, or GitHub API failure fails the workflow
instead of treating an unknown membership as a community author.

## Activation

1. Create an incoming webhook for `#support` (`C0BSD8790F5`) in Tuist Company
   (`T061C1JGAHH`) using the existing GitHub Notifications app (`A0B2Z862NA1`).
   The webhook determines the destination and the app's display identity.
2. Store the webhook URL in the repository Actions secret
   `COMMUNITY_SLACK_WEBHOOK_URL`. Do not commit it or put it in an issue/PR.
3. Verify the existing `TUIST_APP_GITHUB_TOKEN` secret can list members of both
   teams. It needs organization **Members: read** permission; the repository's
   default `GITHUB_TOKEN` cannot provide that access.
4. Merge the workflow into the default branch. Check repository/organization
   Actions event policies permit this `pull_request_target` workflow; GitHub
   may block that event by default. Retain protections on other workflows.
5. Verify a real community issue and fork PR each produce a Slack card, and an
   employee/contractor contribution is skipped. Check the workflow run logs
   when a card is missing. A missing webhook fails eligible notifications.

The PR trigger is `pull_request_target` so fork events can access the webhook.
Checkout is pinned to the trusted event SHA and restricted to `.github/scripts`;
it must never load the PR head, merge commit, or contributor-provided code.
Titles are passed as JSON/plain text, never interpolated into executable code
or Slack markdown. No issue bodies are sent, and link unfurls are disabled.

After correcting a failed run, rerun it in Actions. Rerunning a successfully
delivered event may create a duplicate Slack message: this workflow has no
persistent delivery ledger. Disable the workflow to stop delivery. Rotate the
webhook secret if the destination changes or the URL is exposed.

## Local validation

```sh
node --test .github/scripts/community-notifications.test.cjs
actionlint .github/workflows/community-notifications.yml
```

References: [GitHub privileged PR event guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target),
[Slack incoming webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/).
