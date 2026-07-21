defmodule Tuist.Tests.XcresultProcessingTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Shards.ShardRun
  alias Tuist.Tests
  alias Tuist.Tests.Workers.ProcessXcresultWorker
  alias Tuist.Tests.XcresultProcessing
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

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

  test "deserializes ran_at before persisting a failed sharded run", %{account: account, project: project} do
    test_run_id = UUIDv7.generate()
    ran_at = ~N[2026-07-21 02:59:14.935065]
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)

    assert {:ok, _test} =
             Tests.create_test(%{
               id: test_run_id,
               project_id: project.id,
               account_id: account.id,
               duration: 0,
               status: "processing",
               ran_at: ran_at,
               is_ci: true,
               shard_plan_id: plan.id,
               shard_index: 0
             })

    assert :ok =
             XcresultProcessing.mark_test_run_failed(%{
               "test_run_id" => test_run_id,
               "project_id" => project.id,
               "account_id" => account.id,
               "is_ci" => true,
               "shard_plan_id" => plan.id,
               "shard_index" => 0,
               "ran_at" => "2026-07-21T02:59:14.935065"
             })

    failed_shard_run =
      ClickHouseRepo.one(
        from(shard_run in ShardRun,
          where: shard_run.test_run_id == ^test_run_id,
          where: shard_run.status == "failed_processing",
          limit: 1
        )
      )

    assert failed_shard_run.ran_at == ran_at
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
