defmodule Cache.S3TransferWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3Transfers
  alias Cache.S3TransferWorker
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "perform/1" do
    test "processes pending uploads and deletes them" do
      {:ok, _} = S3Transfers.enqueue_upload("account", "project", "artifact1")
      {:ok, _} = S3Transfers.enqueue_upload("account", "project", "artifact2")

      expect(Cache.S3, :upload, 2, fn _account, _project, _artifact ->
        :ok
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "processes pending downloads and deletes them" do
      {:ok, _} = S3Transfers.enqueue_download("account", "project", "artifact1")
      {:ok, _} = S3Transfers.enqueue_download("account", "project", "artifact2")

      expect(Cache.S3, :download, 2, fn _account, _project, _artifact ->
        :ok
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "processes both uploads and downloads" do
      {:ok, _} = S3Transfers.enqueue_upload("account", "project", "artifact1")
      {:ok, _} = S3Transfers.enqueue_download("account", "project", "artifact2")

      expect(Cache.S3, :upload, fn _account, _project, _artifact ->
        :ok
      end)

      expect(Cache.S3, :download, fn _account, _project, _artifact ->
        :ok
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "deletes transfers on non-retryable failure" do
      {:ok, _} = S3Transfers.enqueue_upload("account", "project", "artifact1")

      expect(Cache.S3, :upload, fn _account, _project, _artifact ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "keeps transfers in queue on rate limiting" do
      {:ok, _} = S3Transfers.enqueue_upload("account", "project", "artifact1")
      {:ok, _} = S3Transfers.enqueue_download("account", "project", "artifact2")

      expect(Cache.S3, :upload, fn _account, _project, _artifact ->
        {:error, :rate_limited}
      end)

      expect(Cache.S3, :download, fn _account, _project, _artifact ->
        {:error, :rate_limited}
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 2
    end

    test "does nothing when no pending transfers" do
      assert :ok = S3TransferWorker.perform(%Oban.Job{})

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end
  end
end
