defmodule Tuist.Tests.XcresultProcessingTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Tests.Workers.ProcessXcresultWorker
  alias Tuist.Tests.XcresultProcessing
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    %{account: account, project: project}
  end

  test "enqueues the processing job", %{account: account, project: project} do
    args = processing_args(account.id, project.id)

    assert {:ok, job} = XcresultProcessing.enqueue(args)
    assert job.max_attempts == 20
    assert_enqueued(worker: ProcessXcresultWorker, args: %{"test_run_id" => args.test_run_id})
  end

  test "enqueues a new job after an earlier matching job completed", %{account: account, project: project} do
    args = processing_args(account.id, project.id)
    {:ok, first_job} = XcresultProcessing.enqueue(args)

    Repo.update_all(from(oban_job in Oban.Job, where: oban_job.id == ^first_job.id),
      set: [state: "completed", completed_at: DateTime.utc_now()]
    )

    assert {:ok, second_job} = XcresultProcessing.enqueue(args)
    refute second_job.id == first_job.id
  end

  test "reuses an older matching job while it is still active", %{account: account, project: project} do
    args = processing_args(account.id, project.id)
    {:ok, first_job} = XcresultProcessing.enqueue(args)

    Repo.update_all(from(oban_job in Oban.Job, where: oban_job.id == ^first_job.id),
      set: [state: "retryable", attempt: 3, inserted_at: DateTime.add(DateTime.utc_now(), -3600)]
    )

    assert {:ok, second_job} = XcresultProcessing.enqueue(args)
    assert second_job.id == first_job.id
  end

  defp processing_args(account_id, project_id) do
    %{
      test_run_id: UUIDv7.generate(),
      storage_key: "account/project/runs/test/result_bundle.zip",
      account_id: account_id,
      project_id: project_id,
      account_handle: "account",
      project_handle: "project",
      is_ci: true
    }
  end
end
