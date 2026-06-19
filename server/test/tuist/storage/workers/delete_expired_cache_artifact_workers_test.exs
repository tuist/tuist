defmodule Tuist.Storage.Workers.DeleteExpiredCacheArtifactWorkersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Storage.CacheArtifactRetention
  alias Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeModuleCacheArtifactsWorker

  describe "perform/1" do
    test "the Xcode cache worker deletes expired Xcode cache artifacts and schedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :xcode_cache, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      assert :ok = perform_job(DeleteExpiredXcodeCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert_enqueued(
        worker: DeleteExpiredXcodeCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the Xcode module cache worker deletes expired module cache artifacts and schedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :xcode_module, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      assert :ok = perform_job(DeleteExpiredXcodeModuleCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert_enqueued(
        worker: DeleteExpiredXcodeModuleCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the Gradle cache worker deletes expired Gradle cache artifacts and schedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :gradle, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      assert :ok = perform_job(DeleteExpiredGradleCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert_enqueued(
        worker: DeleteExpiredGradleCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "the CAS cache worker deletes expired legacy CAS artifacts and schedules the next page" do
      expect(CacheArtifactRetention, :delete_expired, fn :cas, [continuation_token: "cursor"] ->
        {:ok, "next-cursor"}
      end)

      assert :ok = perform_job(DeleteExpiredCasCacheArtifactsWorker, %{"continuation_token" => "cursor"})

      assert_enqueued(
        worker: DeleteExpiredCasCacheArtifactsWorker,
        args: %{"continuation_token" => "next-cursor"}
      )
    end

    test "does not schedule another page when the cache retention scan is complete" do
      expect(CacheArtifactRetention, :delete_expired, fn :gradle, [continuation_token: nil] ->
        {:ok, nil}
      end)

      assert :ok = perform_job(DeleteExpiredGradleCacheArtifactsWorker, %{})

      refute_enqueued(worker: DeleteExpiredGradleCacheArtifactsWorker)
    end
  end
end
