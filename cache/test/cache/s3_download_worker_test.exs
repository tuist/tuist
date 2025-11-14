defmodule Cache.Workers.S3DownloadWorkerTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import ExUnit.CaptureLog

  alias Cache.Repo
  alias Cache.S3DownloadWorker
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "enqueue_download/3" do
    test "enqueues download job" do
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"

      {:ok, _job} = S3DownloadWorker.enqueue_download(account_handle, project_handle, id)

      assert_enqueued(worker: S3DownloadWorker, args: %{key: "test_account/test_project/cas/test_hash"})
    end
  end

  describe "perform/1" do
    test "successfully downloads file from S3 when it exists" do
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(Cache.S3, :exists?, fn ^key -> true end)
      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        File.write!(local_path, "test downloaded content")
        {:ok, %{status_code: 200}}
      end)

      job = %Oban.Job{
        args: %{
          "key" => key
        }
      }

      result = S3DownloadWorker.perform(job)

      assert result == :ok
      assert File.exists?(local_path)
    end

    test "skips download when file does not exist in S3" do
      key = "test_account/test_project/cas/test_hash"
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"

      expect(Cache.S3, :exists?, fn ^key -> false end)

      job = %Oban.Job{
        args: %{
          "key" => key,
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => id
        }
      }

      capture_log(fn ->
        result = S3DownloadWorker.perform(job)
        assert result == :ok
      end)
    end

    test "handles S3 download failure" do
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(Cache.S3, :exists?, fn ^key -> true end)
      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        {:error, :timeout}
      end)

      job = %Oban.Job{
        args: %{
          "key" => key
        }
      }

      assert_raise MatchError, fn ->
        S3DownloadWorker.perform(job)
      end
    end

    test "handles S3 exists? error" do
      key = "test_account/test_project/cas/test_hash"
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"

      expect(Cache.S3, :exists?, fn ^key -> false end)

      job = %Oban.Job{
        args: %{
          "key" => key,
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => id
        }
      }

      capture_log(fn ->
        result = S3DownloadWorker.perform(job)
        assert result == :ok
      end)
    end
  end
end
