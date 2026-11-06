---
{
  "title": "API",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run jobs on Tuist Runners from your own git forge or orchestrator: create a job with one API request and follow it with webhooks."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

Git forges, merge queues, and agent orchestrators that have no runner protocol of their own can run jobs on Tuist Runners directly. You create a job with one request, a Tuist machine of the <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> you choose checks out the commit and runs your script, and Tuist reports the result to your webhook endpoint.

## Run a job {#run-a-job}

1. **Create an account token** with the `account:runners:write` scope:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **Create the job.** A typical caller does this from its push hook, with a short-lived token that lets the machine clone the repository:

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   The response is the job, with its `workflow_job_id`. It appears in the **Runners** section of your Tuist dashboard straight away and starts as soon as a machine of the profile is free. Warm machines usually start it within seconds.

3. **Follow the job.** Subscribe a <.localized_link href="/guides/integrations/webhooks">webhook endpoint</.localized_link> to `runner_job.started` and `runner_job.completed`. The completed event carries the job's `conclusion`: `success`, `failure`, or `cancelled`. You can also poll `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` and read the log from `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`.

## Integrate a git forge {#integrate-a-git-forge}

A forge without a runner protocol connects through a small bridge, which can be a service of the forge itself or a function it calls from its hooks:

1. **On push**, the forge's push hook reaches the bridge. The bridge verifies the hook, decides which checks the commit needs, and mints a read-only clone token for the repository that expires after the job's timeout.
2. **For each check**, the bridge creates a job with `idempotency_key` set to `<repository>:<commit>:<check>`, so a redelivered hook creates nothing new. It stores the returned `workflow_job_id` and can mark the check pending in the forge.
3. **On `runner_job.started` and `runner_job.completed`**, the bridge verifies the `Tuist-Signature` header with the endpoint's secret, finds the check by `workflow_job_id` or `idempotency_key`, and updates the forge's commit status with the `conclusion`. It can link the status to the job's page in the Tuist dashboard.
4. **When a push supersedes a commit**, the bridge cancels the jobs it created for the older commit.

## How the job runs {#how-the-job-runs}

The machine fetches `commit_sha` from `repository_url` over HTTPS. When the server does not serve a commit by its SHA, it fetches `ref` instead, which must contain the commit. The `clone_token`, if you give one, is sent as `Authorization: Bearer <token>` to the repository's host only. It never reaches your script or the job log.

Your script runs with Bash in a login shell, with `set -eo pipefail`, from the root of the checkout. The job fails when the script exits with a non-zero status or runs past `timeout_minutes`, which defaults to 60 and can be up to 360. Besides your `env` and `secrets`, the script sees `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF`, and `TUIST_JOB_COMMIT_SHA`. Values of `secrets` are masked in the job log.

## Retries and idempotency {#idempotency}

Give each job an `idempotency_key` that names what it is for, such as `<repository>:<commit>:<check>`. A request with a key already used in your account returns the existing job, with status 200 instead of 201, and creates nothing. This lets your push hook hand the request to a retry queue without risking duplicate jobs.

Webhook deliveries are retried until your endpoint answers with a 2xx status, so an event can arrive more than once. Use the `id` of the envelope, or the job's `workflow_job_id` with the event type, to deduplicate.

## Cancel a job {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

A job no machine has started is cancelled immediately. A running job stops within a few seconds, and its completed event reports `cancelled`. A job that no machine starts within 24 hours is cancelled automatically.

## Caching and trust {#trust}

Anyone who can push to the repository can change what a job runs, so API jobs are treated as untrusted: they don't get your account's shared <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link> or its cache signing grant. The secrets, script, and clone token of a job are stored encrypted and deleted once the job finishes.
