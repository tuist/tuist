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
    test "processes pending CAS uploads via upload_file with type: :xcode_cache" do
      suffix = :erlang.unique_integer([:positive])
      key_one = "account/project/xcode/ar/ti/artifact1-#{suffix}"
      key_two = "account/project/xcode/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_xcode_upload("account", "project", key_one)
      :ok = S3Transfers.enqueue_xcode_upload("account", "project", key_two)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.Disk, :artifact_path, 2, fn _key -> tmp_file end)

      expect(Cache.S3, :upload_file, 2, fn _key, _path, opts ->
        assert opts == [type: :xcode_cache]
        :ok
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[key_one, key_two]), :count, :id)
      assert count == 0
    end

    test "processes pending CAS downloads with type: :xcode_cache" do
      suffix = :erlang.unique_integer([:positive])
      key_one = "account/project/xcode/ar/ti/artifact1-#{suffix}"
      key_two = "account/project/xcode/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_xcode_download("account", "project", key_one)
      :ok = S3Transfers.enqueue_xcode_download("account", "project", key_two)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.S3, :download, 2, fn _key, opts ->
        assert opts == [type: :xcode_cache]
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

    test "processes both CAS uploads and downloads" do
      suffix = :erlang.unique_integer([:positive])
      upload_key = "account/project/xcode/ar/ti/artifact1-#{suffix}"
      download_key = "account/project/xcode/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_xcode_upload("account", "project", upload_key)
      :ok = S3Transfers.enqueue_xcode_download("account", "project", download_key)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.Disk, :artifact_path, 2, fn _key -> tmp_file end)

      expect(Cache.S3, :upload_file, fn _key, _path, opts ->
        assert opts == [type: :xcode_cache]
        :ok
      end)

      expect(Cache.S3, :download, fn _key, opts ->
        assert opts == [type: :xcode_cache]
        {:ok, :hit}
      end)

      capture_log(fn ->
        assert :ok = S3TransferWorker.perform(%Oban.Job{})
      end)

      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(from(t in S3Transfer, where: t.key in ^[upload_key, download_key]), :count, :id)
      assert count == 0
    end

    test "deletes transfers on non-retryable failure" do
      suffix = :erlang.unique_integer([:positive])
      key = "account/project/xcode/ar/ti/artifact1-#{suffix}"

      :ok = S3Transfers.enqueue_xcode_upload("account", "project", key)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.Disk, :artifact_path, fn _key -> tmp_file end)

      expect(Cache.S3, :upload_file, fn _key, _path, [type: :xcode_cache] ->
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
      upload_key = "account/project/xcode/ar/ti/artifact1-#{suffix}"
      download_key = "account/project/xcode/ar/ti/artifact2-#{suffix}"

      :ok = S3Transfers.enqueue_xcode_upload("account", "project", upload_key)
      :ok = S3Transfers.enqueue_xcode_download("account", "project", download_key)
      :ok = S3TransfersBuffer.flush()

      {:ok, tmp_dir} = Briefly.create(directory: true)
      tmp_file = Path.join(tmp_dir, "test_artifact")
      File.write!(tmp_file, "test content")

      expect(Cache.Disk, :artifact_path, fn _key -> tmp_file end)

      expect(Cache.S3, :upload_file, fn _key, _path, [type: :xcode_cache] ->
        {:error, :rate_limited}
      end)

      expect(Cache.S3, :download, fn _key, [type: :xcode_cache] ->
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
      key = "account/project/xcode/ar/ti/artifact-noop-#{suffix}"

      assert :ok = S3TransferWorker.perform(%Oban.Job{})

      count = Repo.aggregate(from(t in S3Transfer, where: t.key == ^key), :count, :id)
      assert count == 0
    end
  end
end
