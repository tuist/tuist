defmodule Cache.S3TransferWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3Transfers
  alias Cache.S3TransfersBuffer
  alias Cache.S3TransferWorker
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup context do
    :ok = Sandbox.checkout(Repo)

    context = Cache.BufferTestHelpers.setup_s3_transfers_buffer(context)

    {:ok, context}
  end

  describe "perform/1" do
    test "processes pending uploads and deletes them" do
      suffix = :erlang.unique_integer([:positive])
      key_one = "account/project/cas/ar/ti/artifact1-#{suffix}"
      key_two = "account/project/cas/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_cas_upload("account", "project", key_one)
      :ok = S3Transfers.enqueue_cas_upload("account", "project", key_two)
      :ok = S3TransfersBuffer.flush()

      expect(Cache.S3, :upload, 2, fn _key ->
        :ok
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[key_one, key_two]), :count, :id)
      assert count == 0
    end

    test "processes pending downloads and deletes them" do
      suffix = :erlang.unique_integer([:positive])
      key_one = "account/project/cas/ar/ti/artifact1-#{suffix}"
      key_two = "account/project/cas/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_cas_download("account", "project", key_one)
      :ok = S3Transfers.enqueue_cas_download("account", "project", key_two)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.S3, :download, 2, fn _key ->
        {:ok, :hit}
      end)

      expect(Cache.Disk, :artifact_path, 2, fn _key -> tmp_file end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[key_one, key_two]), :count, :id)
      assert count == 0
    end

    test "processes both uploads and downloads" do
      suffix = :erlang.unique_integer([:positive])
      upload_key = "account/project/cas/ar/ti/artifact1-#{suffix}"
      download_key = "account/project/cas/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_cas_upload("account", "project", upload_key)
      :ok = S3Transfers.enqueue_cas_download("account", "project", download_key)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.S3, :upload, fn _key ->
        :ok
      end)

      expect(Cache.S3, :download, fn _key ->
        {:ok, :hit}
      end)

      expect(Cache.Disk, :artifact_path, fn _key -> tmp_file end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[upload_key, download_key]), :count, :id)
      assert count == 0
    end

    test "deletes transfers on non-retryable failure" do
      suffix = :erlang.unique_integer([:positive])
      key = "account/project/cas/ar/ti/artifact1-#{suffix}"

      :ok = S3Transfers.enqueue_cas_upload("account", "project", key)
      :ok = S3TransfersBuffer.flush()

      expect(Cache.S3, :upload, fn _key ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key == ^key), :count, :id)
      assert count == 0
    end

    test "keeps transfers in queue on rate limiting" do
      suffix = :erlang.unique_integer([:positive])
      upload_key = "account/project/cas/ar/ti/artifact1-#{suffix}"
      download_key = "account/project/cas/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_cas_upload("account", "project", upload_key)
      :ok = S3Transfers.enqueue_cas_download("account", "project", download_key)
      :ok = S3TransfersBuffer.flush()

      expect(Cache.S3, :upload, fn _key ->
        {:error, :rate_limited}
      end)

      expect(Cache.S3, :download, fn _key ->
        {:error, :rate_limited}
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[upload_key, download_key]), :count, :id)
      assert count == 2
    end

    test "does nothing when no pending transfers" do
      suffix = :erlang.unique_integer([:positive])
      key = "account/project/cas/ar/ti/artifact-noop-#{suffix}"

      assert :ok = S3TransferWorker.perform(%Oban.Job{})

      count = Repo.aggregate(from(t in S3Transfer, where: t.key == ^key), :count, :id)
      assert count == 0
    end
  end
end
