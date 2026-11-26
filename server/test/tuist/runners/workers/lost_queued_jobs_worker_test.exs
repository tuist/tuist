defmodule Tuist.Runners.Workers.LostQueuedJobsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Workers.LostQueuedJobsWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    cache = :"runners_dispatch_#{System.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache})
    stub(Dispatch, :cache_name, fn -> cache end)
    stub(Catalog, :default_xcode_version, fn -> nil end)

    # The real dispatch path resolves `tuist-macos-26-6` to this pool and
    # nothing else, so `ubuntu-latest` is not ours.
    stub(KubernetesClient, :list_runner_pools, fn _ns ->
      {:ok, [%{"metadata" => %{"name" => "macos-26-6-pool"}, "spec" => %{"dispatchLabel" => "tuist-macos-26-6"}}]}
    end)

    account = AccountsFixtures.organization_fixture(name: "tuist-#{System.unique_integer([:positive])}").account
    Concurrency.raise_to_plan_defaults(account, :pro)

    stub(Tuist.VCS, :get_github_app_installation_for_account, fn id ->
      assert id == account.id
      {:ok, %{installation_id: "4242", client_url: "https://github.com"}}
    end)

    %{account: account}
  end

  defp enqueue_row(account, workflow_job_id, run_id, enqueued_at) do
    :ok =
      WorkflowJobs.upsert_queued(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "pool",
        repository: "tuist/tuist",
        workflow_run_id: run_id,
        workflow_name: "Server Production Deployment",
        run_attempt: 1,
        job_name: "Acceptance Tests",
        head_branch: "main",
        head_sha: "abc",
        enqueued_at: enqueued_at
      })
  end

  defp gh_job(id, status, labels, created_ago_seconds) do
    created_at = DateTime.utc_now() |> DateTime.add(-created_ago_seconds, :second) |> DateTime.to_iso8601()

    job = %{
      "id" => id,
      "status" => status,
      "labels" => labels,
      "run_id" => 45_650_194_221,
      "created_at" => created_at,
      "name" => "job-#{id}"
    }

    %{id: id, status: status, runner_name: nil, job: job}
  end

  test "enqueues only the run's Tuist jobs GitHub holds queued past the grace with no lifecycle row", %{account: account} do
    run_id = 45_650_194_221
    enqueue_row(account, 1, run_id, DateTime.add(DateTime.utc_now(), -10, :minute))

    expect(GitHubClient, :list_workflow_run_jobs, fn _installation, "tuist/tuist", ^run_id ->
      {:ok,
       [
         # Received: has a lifecycle row.
         gh_job(1, "queued", ["tuist-macos-26-6"], 600),
         # Lost: queued for 10 minutes, nothing on our side.
         gh_job(2, "queued", ["tuist-macos-26-6"], 600),
         # Webhook may still be in flight.
         gh_job(3, "queued", ["tuist-macos-26-6"], 30),
         # Not ours.
         gh_job(4, "queued", ["ubuntu-latest"], 600),
         # Already running somewhere.
         gh_job(5, "in_progress", ["tuist-macos-26-6"], 600)
       ]}
    end)

    # Only the lost job reaches dispatch: the rest would log an ignore or
    # take the per-job lock every tick.
    expect(Dispatch, :handle_webhook, 1, fn payload, installation_id, account_id ->
      assert installation_id == 4242
      assert account_id == account.id
      Mimic.call_original(Dispatch, :handle_webhook, [payload, installation_id, account_id])
    end)

    assert :ok = LostQueuedJobsWorker.perform(%Oban.Job{})

    rows = Repo.all(from(j in WorkflowJob, where: j.account_id == ^account.id, order_by: j.workflow_job_id))

    assert [
             %WorkflowJob{workflow_job_id: 1},
             %WorkflowJob{
               workflow_job_id: 2,
               status: "queued",
               fleet_name: "macos-26-6-pool",
               repository: "tuist/tuist",
               workflow_run_id: ^run_id,
               job_name: "job-2"
             }
           ] = rows
  end

  test "does not poll runs whose last enqueued job is older than the lookback", %{account: account} do
    enqueue_row(account, 10, 777, DateTime.add(DateTime.utc_now(), -2, :hour))

    reject(&GitHubClient.list_workflow_run_jobs/3)
    reject(&Dispatch.handle_webhook/3)

    assert :ok = LostQueuedJobsWorker.perform(%Oban.Job{})
  end

  test "a failed run lookup leaves the tick healthy", %{account: account} do
    enqueue_row(account, 20, 888, DateTime.utc_now())

    expect(GitHubClient, :list_workflow_run_jobs, fn _installation, "tuist/tuist", 888 -> {:error, {:http, 502, ""}} end)
    reject(&Dispatch.handle_webhook/3)

    assert :ok = LostQueuedJobsWorker.perform(%Oban.Job{})
  end
end
