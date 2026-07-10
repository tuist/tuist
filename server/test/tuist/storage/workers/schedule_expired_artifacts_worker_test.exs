defmodule Tuist.Storage.Workers.ScheduleExpiredArtifactsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage.Workers.DeleteExpiredBuildArchivesWorker
  alias Tuist.Storage.Workers.DeleteExpiredPreviewArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredRunSessionsWorker
  alias Tuist.Storage.Workers.DeleteExpiredShardBundlesWorker
  alias Tuist.Storage.Workers.DeleteExpiredTestAttachmentsWorker
  alias Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker

  describe "perform/1" do
    test "scheduler and account workers keep active jobs unique until completion" do
      scheduler_unique = ScheduleExpiredArtifactsWorker.new(%{}).changes.unique

      assert scheduler_unique.fields == [:queue, :worker]
      assert scheduler_unique.period == :infinity
      assert scheduler_unique.states == [:available, :scheduled, :executing, :retryable]

      Enum.each(ScheduleExpiredArtifactsWorker.deletion_workers(), fn worker ->
        unique = worker.new(%{}).changes.unique

        assert unique.keys == [:account_id]
        assert unique.period == :infinity
        assert unique.states == [:available, :scheduled, :executing, :retryable]
      end)
    end

    test "enqueues one deletion job per account and artifact type and reschedules the next page" do
      after_id = max_account_id()
      first_account = account_fixture()
      second_account = account_fixture()
      [first_account_id, _second_account_id] = Enum.sort([first_account.id, second_account.id])
      args = %{"after_id" => after_id, "batch_size" => 10, "page_size" => 1}

      assert {:ok, pending_job} = args |> ScheduleExpiredArtifactsWorker.new() |> Oban.insert()
      assert {:snooze, 0} = ScheduleExpiredArtifactsWorker.perform(pending_job)

      assert_deletion_jobs_enqueued(first_account_id)

      assert [continuation_job] = all_enqueued(worker: ScheduleExpiredArtifactsWorker)
      assert continuation_job.id == pending_job.id

      assert continuation_job.args == %{
               "after_id" => first_account_id,
               "page_size" => 1,
               "batch_size" => 10
             }
    end

    test "continues from the provided account cursor" do
      first_account = account_fixture()
      second_account = account_fixture()
      [first_account_id, second_account_id] = Enum.sort([first_account.id, second_account.id])

      assert :ok =
               perform_job(ScheduleExpiredArtifactsWorker, %{
                 "after_id" => first_account_id,
                 "batch_size" => 10,
                 "page_size" => 1
               })

      assert_deletion_jobs_enqueued(second_account_id)
    end

    test "enqueues only configured resource types and preserves their windows across account pages" do
      after_id = max_account_id()
      first_account = account_fixture()
      _second_account = account_fixture()
      queued_retention_days = %{"app_previews" => 30, "build_archives" => 30}
      current_retention_days = %{"app_previews" => 45, "run_artifacts" => 60}

      stub(Environment, :artifact_retention_days, fn -> %{app_previews: 45, run_artifacts: 60} end)

      args = %{
        "after_id" => after_id,
        "batch_size" => 10,
        "page_size" => 1,
        "retention_days" => queued_retention_days,
        "self_hosted" => true
      }

      assert {:ok, pending_job} = args |> ScheduleExpiredArtifactsWorker.new() |> Oban.insert()
      assert {:snooze, 0} = ScheduleExpiredArtifactsWorker.perform(pending_job)

      assert_enqueued(
        worker: DeleteExpiredPreviewArtifactsWorker,
        args: %{
          "account_id" => first_account.id,
          "batch_size" => 10,
          "retention_days" => 45,
          "self_hosted" => true
        }
      )

      assert_enqueued(
        worker: DeleteExpiredRunSessionsWorker,
        args: %{
          "account_id" => first_account.id,
          "batch_size" => 10,
          "retention_days" => 60,
          "self_hosted" => true
        }
      )

      refute_enqueued(worker: DeleteExpiredBuildArchivesWorker)
      refute_enqueued(worker: DeleteExpiredTestAttachmentsWorker)
      refute_enqueued(worker: DeleteExpiredShardBundlesWorker)

      assert_enqueued(
        worker: ScheduleExpiredArtifactsWorker,
        args: %{
          "after_id" => first_account.id,
          "page_size" => 1,
          "batch_size" => 10,
          "retention_days" => current_retention_days,
          "self_hosted" => true
        }
      )
    end

    test "does not enqueue deletion jobs for an empty account page" do
      assert :ok = perform_job(ScheduleExpiredArtifactsWorker, %{"after_id" => max_account_id(), "page_size" => 1})

      Enum.each(ScheduleExpiredArtifactsWorker.deletion_workers(), fn deletion_worker ->
        refute_enqueued(worker: deletion_worker)
      end)
    end

    test "self-hosted scheduling enforces deletion job uniqueness" do
      after_id = max_account_id()
      account = account_fixture()

      stub(Environment, :artifact_retention_days, fn -> %{app_previews: 30} end)

      args = %{
        "after_id" => after_id,
        "page_size" => 500,
        "retention_days" => %{"app_previews" => 30},
        "self_hosted" => true
      }

      assert :ok = perform_job(ScheduleExpiredArtifactsWorker, args)
      assert :ok = perform_job(ScheduleExpiredArtifactsWorker, args)

      assert [job] = all_enqueued(worker: DeleteExpiredPreviewArtifactsWorker)
      assert job.args["account_id"] == account.id
    end

    test "a queued self-hosted scheduler stops when no account artifacts are configured" do
      _account = account_fixture()
      stub(Environment, :artifact_retention_days, fn -> %{cache_artifacts: 30} end)

      assert :ok =
               perform_job(ScheduleExpiredArtifactsWorker, %{
                 "retention_days" => %{"app_previews" => 30},
                 "self_hosted" => true
               })

      Enum.each(ScheduleExpiredArtifactsWorker.deletion_workers(), fn deletion_worker ->
        refute_enqueued(worker: deletion_worker)
      end)

      refute_enqueued(worker: ScheduleExpiredArtifactsWorker)
    end
  end

  defp assert_deletion_jobs_enqueued(account_id) do
    Enum.each(ScheduleExpiredArtifactsWorker.deletion_workers(), fn deletion_worker ->
      assert_enqueued(
        worker: deletion_worker,
        args: %{"account_id" => account_id, "batch_size" => 10}
      )
    end)
  end

  defp max_account_id do
    Repo.one(from account in Account, select: max(account.id)) || 0
  end
end
