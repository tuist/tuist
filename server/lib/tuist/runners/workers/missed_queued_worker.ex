defmodule Tuist.Runners.Workers.MissedQueuedWorker do
  @moduledoc """
  Recovers `workflow_job.queued` webhook deliveries GitHub dropped
  or our endpoint missed.

  ## Why this exists

  The `workflow_job: queued` webhook is the **only** path that
  inserts a row into ClickHouse `runner_jobs`. `OrphanedRunnersWorker`
  reconciles rows already in CH `status='running'` against GitHub —
  it cannot recover a `queued` event that was never delivered to
  the webhook endpoint at all. If GitHub drops a delivery (provider
  outage, our endpoint 5xx'd, signature failure, replay-after-deploy
  window), the customer's workflow_job sits in GitHub's queue
  indefinitely with no row, no metric, no alert on our side.

  ## How it works

  Every 5 minutes:

    1. List accounts with `runner_max_concurrent > 0`. Customers
       who haven't enabled runners can't be the target of this
       failure and we don't want to burn API budget enumerating
       their repos.

    2. For each enabled account, resolve the GitHub App
       installation via `Tuist.VCS.get_github_app_installation_for_account/1`.

    3. List the installation's repositories (paginated via the
       existing `GitHubClient.list_installation_repositories/2`).

    4. For each repo, GET `/actions/runs?status=queued&created>=...`
       with a `@lookback_minutes`-wide window. `created>=` caps the
       blast radius so an outage that left thousands of ancient
       runs in `queued` doesn't suddenly cost us an unbounded
       number of API calls.

    5. For each queued run, GET `/actions/runs/{run_id}/jobs?filter=latest`
       to enumerate its jobs. Run-level queries don't include
       per-job labels, which we need to decide pool routing.

    6. For each job in `status='queued'` whose `labels` match one
       of our `RunnerPool.spec.dispatchLabel`s, check
       `Jobs.exists?(workflow_job_id)`. If the row already exists
       (webhook arrived, just slightly delayed), skip. Otherwise
       INSERT via `Jobs.enqueue/1` using the same payload shape
       the webhook handler builds.

  ## Cadence and lookback

  Cron `*/5 * * * *` with `@lookback_minutes = 15` gives 3x overlap
  against intermittent failures: a webhook dropped at T receives
  three chances to be recovered before falling out of the window
  at T+15.

  Recovery latency is bounded by the cron period (up to 5 min) plus
  the time it takes the worker to reach that customer's repo in its
  iteration. Acceptable trade against API cost — every-minute
  cadence would push us close to the 5000/hr per-installation rate
  limit for customers with many repos.

  ## Cost shape

  Per cycle per enabled account: `1 + R` API calls for the empty
  case (list repos + list-queued-runs per repo), and an additional
  call per queued run found. Queued runs in any given 15-min window
  are usually 0; the steady-state cost is dominated by the empty
  list-runs calls. At 100 repos per customer that's ~1200 calls/hr
  per installation, well inside the 5000/hr installation limit.

  ## Idempotency and race against late webhooks

  `Jobs.exists?/1` is the dedup gate — if the webhook landed
  between our list-jobs call and our enqueue call, the second
  enqueue is dropped. If the webhook lands AFTER our enqueue, RMT
  on the CH side collapses to one logical row (both INSERTs carry
  `status='queued'`, the later `updated_at` wins on merge, the
  outcome is identical to a single delivery).

  Telemetry: emits `tuist_runners_recovery_count{kind="missed_queued"}`
  per successful recovery — feeds the Grafana dashboard's recovery
  rate panel alongside `stale_claim` / `orphan_requeued` / `orphan_completed`.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.VCS

  require Logger

  @lookback_minutes 15

  # GitHub-side "queued for at least this long" gate. Without it,
  # the worker races every legitimately-delivered webhook — a
  # workflow_job that arrived 2s ago hasn't had time to traverse
  # webhook → DispatchWorker → CH enqueue, but it's already in
  # GitHub's queue and would look "missed" from our side. The
  # threshold gives the normal path comfortably enough time to
  # complete before we second-guess it.
  @min_age_seconds 60

  @impl Oban.Worker
  def perform(_job) do
    recovered =
      Enum.reduce(Accounts.list_accounts_with_runners_enabled(), 0, fn account, acc ->
        acc + recover_for_account(account)
      end)

    if recovered > 0 do
      Logger.warning("runners: recovered missed-queued webhooks",
        count: recovered,
        lookback_minutes: @lookback_minutes
      )
    end

    :ok
  end

  defp recover_for_account(account) do
    case VCS.get_github_app_installation_for_account(account.id) do
      {:ok, installation} ->
        installation
        |> list_repos_safely(account)
        |> Enum.reduce(0, fn repo, acc ->
          acc + recover_for_repo(installation, account, repo)
        end)

      {:error, :not_found} ->
        0

      {:error, reason} ->
        Logger.warning("runners: missed-queued worker installation lookup failed",
          account: account.name,
          reason: inspect(reason)
        )

        0
    end
  end

  defp list_repos_safely(installation, account) do
    {:start, nil}
    |> Stream.unfold(fn
      :done ->
        nil

      {:start, _} ->
        fetch_repos_page(installation, account, [])

      {:cont, next_url} ->
        fetch_repos_page(installation, account, next_url: next_url)
    end)
    |> Stream.flat_map(& &1)
    |> Enum.to_list()
  end

  defp fetch_repos_page(installation, account, opts) do
    case GitHubClient.list_installation_repositories(installation, opts) do
      {:ok, %{meta: %{next_url: nil}, repositories: repos}} ->
        {repos, :done}

      {:ok, %{meta: %{next_url: next_url}, repositories: repos}} ->
        {repos, {:cont, next_url}}

      {:error, reason} ->
        Logger.warning("runners: missed-queued worker repo list failed",
          account: account.name,
          reason: inspect(reason)
        )

        nil
    end
  end

  defp recover_for_repo(installation, account, repo) do
    full_name = repo[:full_name] || ""

    case GitHubClient.list_queued_workflow_runs(installation, full_name, created_after: lookback_threshold()) do
      {:ok, runs} ->
        Enum.reduce(runs, 0, fn run, acc ->
          acc + recover_for_run(installation, account, full_name, run)
        end)

      {:error, :not_found} ->
        # The installation lost access to the repo between our
        # list_repos call and now (uninstall, permission change).
        # Not our concern; skip.
        0

      {:error, reason} ->
        Logger.warning("runners: missed-queued worker list-runs failed",
          account: account.name,
          repo: full_name,
          reason: inspect(reason)
        )

        0
    end
  end

  defp recover_for_run(installation, account, full_name, %{id: run_id}) when is_integer(run_id) do
    case GitHubClient.list_workflow_run_jobs(installation, full_name, run_id) do
      {:ok, jobs} ->
        jobs
        |> Enum.filter(&queued_long_enough?/1)
        |> Enum.count(&recover_for_job(account, full_name, &1))

      {:error, :not_found} ->
        0

      {:error, reason} ->
        Logger.warning("runners: missed-queued worker list-jobs failed",
          account: account.name,
          repo: full_name,
          run_id: run_id,
          reason: inspect(reason)
        )

        0
    end
  end

  defp recover_for_run(_installation, _account, _full_name, _), do: 0

  defp queued_long_enough?(%{status: "queued", created_at: %DateTime{} = created_at}) do
    DateTime.diff(DateTime.utc_now(), created_at, :second) >= @min_age_seconds
  end

  defp queued_long_enough?(_), do: false

  defp recover_for_job(account, full_name, job) do
    case Dispatch.match_pool(job.labels) do
      {:ok, %{name: fleet_name}} ->
        do_recover(account, full_name, fleet_name, job)

      {:error, _reason} ->
        # Job's `runs-on` doesn't target our pools. Could be a
        # different runner provider, GitHub-hosted runners, or a
        # typo. Either way, not ours to enqueue.
        false
    end
  end

  defp do_recover(account, full_name, fleet_name, job) do
    workflow_job_id = job.id

    cond do
      not is_integer(workflow_job_id) ->
        false

      Jobs.exists?(workflow_job_id) ->
        false

      true ->
        :ok =
          Jobs.enqueue(%{
            workflow_job_id: workflow_job_id,
            account_id: account.id,
            fleet_name: fleet_name,
            repo: full_name,
            workflow_run_id: job.run_id || 0,
            run_attempt: job.run_attempt || 1,
            job_name: job.name,
            head_branch: job.head_branch,
            head_sha: job.head_sha
          })

        Logger.warning("runners: recovered missed-queued workflow_job",
          account: account.name,
          repo: full_name,
          fleet: fleet_name,
          workflow_job_id: workflow_job_id
        )

        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: 1},
          %{kind: "missed_queued"}
        )

        true
    end
  end

  defp lookback_threshold do
    DateTime.add(DateTime.utc_now(), -@lookback_minutes * 60, :second)
  end
end
