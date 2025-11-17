defmodule Cache.Workers.S3UploadWorkerTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import ExUnit.CaptureLog

  alias Cache.Repo
  alias Cache.S3UploadWorker
  alias Ecto.Adapters.SQL.Sandbox
  alias ExAws.S3.Upload

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "enqueue_upload/3" do
    test "enqueues upload job" do
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"

      {:ok, _job} = S3UploadWorker.enqueue_upload(account_handle, project_handle, id)

      assert_enqueued(worker: S3UploadWorker, args: %{key: "test_account/test_project/cas/test_hash"})
    end
  end

  describe "perform/1" do
    test "successfully uploads file to S3" do
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path ->
        %Upload{src: local_path, bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn _upload -> {:ok, %{status_code: 200}} end)

      job = %Oban.Job{
        args: %{"key" => key}
      }

      result = S3UploadWorker.perform(job)

      assert result == :ok
    end

    test "handles S3 upload failure" do
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path ->
        %Upload{src: local_path, bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn _upload -> {:error, :timeout} end)

      job = %Oban.Job{
        args: %{"key" => key}
      }

      capture_log(fn ->
        result = S3UploadWorker.perform(job)
        assert result == {:error, :timeout}
      end)
    end

    test "handles file not found error" do
      key = "test_account/test_project/cas/test_hash"
      local_path = "/nonexistent/path"

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path ->
        %Upload{src: local_path, bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn _upload -> {:error, %File.Error{}} end)

      job = %Oban.Job{
        args: %{"key" => key}
      }

      capture_log(fn ->
        result = S3UploadWorker.perform(job)
        assert result == {:error, %File.Error{}}
      end)
    end
  end
end
