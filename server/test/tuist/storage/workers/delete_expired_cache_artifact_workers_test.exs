defmodule Tuist.Storage.Workers.DeleteExpiredCacheArtifactWorkersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage.CacheArtifactRetention
  alias Tuist.Storage.LegacyBuildArtifactRetention
  alias Tuist.Storage.Workers.ArtifactRetentionWorker
  alias Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredLegacyBuildArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeModuleCacheArtifactsWorker

  describe "perform/1" do
    test "bucket workers keep active jobs unique until completion" do
      workers = [
        DeleteExpiredXcodeCacheArtifactsWorker,
        DeleteExpiredXcodeModuleCacheArtifactsWorker,
        DeleteExpiredGradleCacheArtifactsWorker,
        DeleteExpiredCasCacheArtifactsWorker,
        DeleteExpiredLegacyBuildArtifactsWorker
      ]

      Enum.each(workers, fn worker ->
        unique = worker.new(%{}).changes.unique

        assert unique.fields == [:queue, :worker]
        assert unique.period == :infinity
        assert unique.states == [:available, :scheduled, :executing, :retryable]
      end)
    end

    test "bucket worker uniqueness blocks a different window or continuation while another replica executes it" do
      assert {:ok, first_job} =
               %{"retention_days" => 30}
               |> DeleteExpiredXcodeCacheArtifactsWorker.new()
               |> Oban.insert()

      {1, _jobs} =
        Repo.update_all(from(job in Oban.Job, where: job.id == ^first_job.id), set: [state: "executing"])

      assert {:ok, second_job} =
               %{"continuation_token" => "next", "retention_days" => 90}
               |> DeleteExpiredXcodeCacheArtifactsWorker.new()
               |> Oban.insert()

      assert second_job.conflict?
      assert second_job.id == first_job.id
    end

    test "rescheduling renews the retry budget for the next page" do
      job = insert_job(DeleteExpiredXcodeCacheArtifactsWorker, %{})

      assert {:snooze, 0} =
               ArtifactRetentionWorker.reschedule_with_args(%{job | attempt: 7}, %{"continuation_token" => "next"})

      assert [updated_job] = all_enqueued(worker: DeleteExpiredXcodeCacheArtifactsWorker)
      assert updated_job.args == %{"continuation_token" => "next"}
      assert updated_job.max_attempts == 9
    end

    test "the Xcode cache worker deletes expired Xcode cache artifacts and reschedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :xcode_cache, opts ->
        assert opts[:continuation_token] == "cursor"
        assert opts[:retention_days] == 60
        {:ok, "next-cursor"}
      end)

      job =
        insert_job(DeleteExpiredXcodeCacheArtifactsWorker, %{"continuation_token" => "cursor", "retention_days" => 60})

      assert {:snooze, 0} = DeleteExpiredXcodeCacheArtifactsWorker.perform(job)

      assert_enqueued(
        worker: DeleteExpiredXcodeCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor", "retention_days" => 60}
      )
    end

    test "the Xcode module cache worker deletes expired module cache artifacts and reschedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :xcode_module, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      job = insert_job(DeleteExpiredXcodeModuleCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert {:snooze, 0} = DeleteExpiredXcodeModuleCacheArtifactsWorker.perform(job)

      assert_enqueued(
        worker: DeleteExpiredXcodeModuleCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the Gradle cache worker deletes expired Gradle cache artifacts and reschedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :gradle, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      job = insert_job(DeleteExpiredGradleCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert {:snooze, 0} = DeleteExpiredGradleCacheArtifactsWorker.perform(job)

      assert_enqueued(
        worker: DeleteExpiredGradleCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the CAS cache worker deletes expired legacy CAS artifacts and reschedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :cas, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      job = insert_job(DeleteExpiredCasCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert {:snooze, 0} = DeleteExpiredCasCacheArtifactsWorker.perform(job)

      assert_enqueued(
        worker: DeleteExpiredCasCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the legacy build artifact worker deletes expired legacy build artifacts and reschedules the next page" do
      expect(LegacyBuildArtifactRetention, :delete_expired, fn opts ->
        assert opts[:continuation_token] == "cursor"
        assert opts[:retention_days] == 90
        {:ok, "next-cursor"}
      end)

      job =
        insert_job(DeleteExpiredLegacyBuildArtifactsWorker, %{
          "continuation_token" => "cursor",
          "retention_days" => 90
        })

      assert {:snooze, 0} = DeleteExpiredLegacyBuildArtifactsWorker.perform(job)

      assert_enqueued(
        worker: DeleteExpiredLegacyBuildArtifactsWorker,
        args: %{"continuation_token" => "next-cursor", "retention_days" => 90}
      )
    end

    test "does not schedule another page when the cache retention scan is complete" do
      expect(CacheArtifactRetention, :delete_expired, fn :gradle, [continuation_token: nil] ->
        {:ok, nil}
      end)

      assert :ok = perform_job(DeleteExpiredGradleCacheArtifactsWorker, %{})

      refute_enqueued(worker: DeleteExpiredGradleCacheArtifactsWorker)
    end

    test "self-hosted workers use the current window for every page" do
      stub(Environment, :artifact_retention_days, fn -> %{cache_artifacts: 90} end)

      assert {:ok, pending_job} =
               %{"retention_days" => 30, "self_hosted" => true}
               |> DeleteExpiredXcodeCacheArtifactsWorker.new()
               |> Oban.insert()

      expect(CacheArtifactRetention, :delete_expired, fn :xcode_cache, opts ->
        assert opts[:retention_days] == 90
        {:ok, "next-cursor"}
      end)

      assert {:snooze, 0} = DeleteExpiredXcodeCacheArtifactsWorker.perform(pending_job)

      assert [continuation_job] = all_enqueued(worker: DeleteExpiredXcodeCacheArtifactsWorker)
      assert continuation_job.id == pending_job.id

      assert continuation_job.args == %{
               "continuation_token" => "next-cursor",
               "retention_days" => 90,
               "self_hosted" => true
             }
    end

    test "self-hosted workers stop when their resource type is disabled" do
      stub(Environment, :artifact_retention_days, fn -> %{} end)
      reject(&CacheArtifactRetention.delete_expired/2)

      assert :ok =
               perform_job(DeleteExpiredXcodeCacheArtifactsWorker, %{
                 "retention_days" => 30,
                 "self_hosted" => true
               })

      refute_enqueued(worker: DeleteExpiredXcodeCacheArtifactsWorker)
    end
  end

  defp insert_job(worker, args) do
    assert {:ok, job} = args |> worker.new() |> Oban.insert()
    job
  end
end
