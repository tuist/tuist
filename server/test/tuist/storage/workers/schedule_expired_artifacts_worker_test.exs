defmodule Tuist.Storage.Workers.ScheduleExpiredArtifactsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker

  describe "perform/1" do
    test "enqueues one deletion job per account and artifact type and schedules the next page" do
      after_id = max_account_id()
      first_account = account_fixture()
      second_account = account_fixture()
      [first_account_id, _second_account_id] = Enum.sort([first_account.id, second_account.id])

      assert :ok =
               perform_job(ScheduleExpiredArtifactsWorker, %{
                 "after_id" => after_id,
                 "batch_size" => 10,
                 "page_size" => 1
               })

      assert_deletion_jobs_enqueued(first_account_id)

      assert_enqueued(
        worker: ScheduleExpiredArtifactsWorker,
        args: %{"after_id" => first_account_id, "page_size" => 1, "batch_size" => 10}
      )
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

    test "does not enqueue deletion jobs for an empty account page" do
      assert :ok = perform_job(ScheduleExpiredArtifactsWorker, %{"after_id" => max_account_id(), "page_size" => 1})

      Enum.each(ScheduleExpiredArtifactsWorker.deletion_workers(), fn deletion_worker ->
        refute_enqueued(worker: deletion_worker)
      end)
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
