defmodule Tuist.Runners.Workers.MissedQueuedWorker do
  @moduledoc """
  Recovers `workflow_job.queued` webhook deliveries GitHub dropped
  or our endpoint missed.

  The webhook is the only path that inserts a row into CH
  `runner_jobs`. `OrphanedRunnersWorker` reconciles rows already in
  `status='running'` — it can't recover a `queued` event that was
  never delivered at all. Without this worker, a dropped delivery
  leaves the customer's workflow_job stuck in GitHub's queue
  indefinitely with no row, no metric, no alert on our side.

  For each account with `runner_max_concurrent > 0`, walks the
  installation's repos, lists `?status=queued` workflow runs in a
  `@lookback_minutes` window, and for any job with a matching pool
  label that we don't already have in CH (`Jobs.exists?/1`), calls
  `Jobs.enqueue/1`.

  Emits `tuist_runners_recovery_count{kind="missed_queued"}` per
  recovery alongside the existing `stale_claim` / `orphan_*` kinds.
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
