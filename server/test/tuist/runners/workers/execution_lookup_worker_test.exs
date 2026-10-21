defmodule Tuist.Runners.Workers.ExecutionLookupWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import ExUnit.CaptureLog
  import Mimic

  alias Tuist.GitHub.Client
  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Workers.ExecutionLookupWorker
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  require Logger

  setup :verify_on_exit!

  setup do
    account = AccountsFixtures.account_fixture()
    VCSFixtures.github_app_installation_fixture(account_id: account.id)
    %{account: account}
  end

  defp workflow_job(account, attrs) do
    Repo.insert!(
      struct(
        WorkflowJob,
        Map.merge(
          %{
            workflow_job_id: System.unique_integer([:positive]),
            account_id: account.id,
            provider: "github",
            fleet_name: "linux",
            status: "running",
            repository: "org/repo",
            workflow_run_id: System.unique_integer([:positive]),
            enqueued_at: DateTime.utc_now()
          },
          attrs
        )
      )
    )
  end

  defp session(account, %WorkflowJob{} = minted, attrs \\ %{}) do
    Repo.insert!(
      struct(
        RunnerSession,
        Map.merge(
          %{
            account_id: account.id,
            workflow_job_id: minted.workflow_job_id,
            fleet_name: "linux",
            pod_name: "pod",
            runner_name: "pod-runner",
            node_name: "node",
            platform: :linux,
            vcpus: 2,
            memory_gb: 8,
            billing_multiplier: 10_000,
            started_at: DateTime.utc_now()
          },
          attrs
        )
      )
    )
  end

  defp perform(%RunnerSession{id: id}), do: perform_job(ExecutionLookupWorker, %{session_id: id})

  test "binds the minted job GitHub reports running on the session's runner", %{account: account} do
    minted = workflow_job(account, %{})
    session = session(account, minted)

    expect(Client, :list_workflow_run_jobs, fn _installation, "org/repo", run_id ->
      assert run_id == minted.workflow_run_id

      {:ok,
       [
         %{id: System.unique_integer([:positive]), status: "in_progress", runner_name: "other-runner"},
         %{id: minted.workflow_job_id, status: "in_progress", runner_name: "pod-runner"}
       ]}
    end)

    assert :ok = perform(session)
    assert Repo.reload!(session).executed_workflow_job_id == minted.workflow_job_id
  end

  test "binds a job from another active run in the fleet when GitHub placed it on the runner", %{account: account} do
    minted = workflow_job(account, %{})
    executed = workflow_job(account, %{repository: "org/other", status: "queued"})
    workflow_job(account, %{fleet_name: "macos", repository: "org/macos"})
    session = session(account, minted)

    expect(Client, :list_workflow_run_jobs, 2, fn
      _installation, "org/repo", _run_id ->
        {:ok, [%{id: minted.workflow_job_id, status: "queued", runner_name: nil}]}

      _installation, "org/other", run_id ->
        assert run_id == executed.workflow_run_id
        {:ok, [%{id: executed.workflow_job_id, status: "in_progress", runner_name: "pod-runner"}]}
    end)

    assert :ok = perform(session)
    assert Repo.reload!(session).executed_workflow_job_id == executed.workflow_job_id
  end

  test "leaves the session unbound when no run has a job running on its runner", %{account: account} do
    Logger.put_module_level(ExecutionLookupWorker, :info)
    on_exit(fn -> Logger.delete_module_level(ExecutionLookupWorker) end)
    minted = workflow_job(account, %{})
    session = session(account, minted)

    expect(Client, :list_workflow_run_jobs, fn _installation, _repository, _run_id ->
      {:ok, [%{id: minted.workflow_job_id, status: "completed", runner_name: "pod-runner"}]}
    end)

    log = capture_log([level: :info], fn -> assert :ok = perform(session) end)

    assert log =~ "execution lookup found no job GitHub reports running on this runner"
    assert is_nil(Repo.reload!(session).executed_workflow_job_id)
  end

  test "never reads another account's runs in the same fleet", %{account: account} do
    other_account = AccountsFixtures.account_fixture()
    workflow_job(other_account, %{repository: "other-org/repo"})
    minted = workflow_job(account, %{})
    session = session(account, minted)

    expect(Client, :list_workflow_run_jobs, fn _installation, "org/repo", _run_id ->
      {:ok, [%{id: minted.workflow_job_id, status: "queued", runner_name: nil}]}
    end)

    assert :ok = perform(session)
    assert is_nil(Repo.reload!(session).executed_workflow_job_id)
  end

  test "skips sessions that are already bound, closed or not GitHub", %{account: account} do
    reject(&Client.list_workflow_run_jobs/3)
    minted = workflow_job(account, %{})

    assert :ok = perform(session(account, minted, %{executed_workflow_job_id: minted.workflow_job_id}))
    assert :ok = perform(session(account, minted, %{ended_at: DateTime.utc_now()}))
    assert :ok = perform(session(account, workflow_job(account, %{provider: "buildkite"})))
  end
end
