defmodule Cache.Workers.S3DownloadWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

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

      expect(Oban, :insert, fn changeset ->
        {:ok,
         %{
           changeset
           | changes:
               Map.put(changeset.changes, :args, %{
                 "account_handle" => "test_account",
                 "project_handle" => "test_project",
                 "id" => "test_hash"
               })
         }}
      end)

      capture_log(fn ->
        {:ok, changeset} = S3DownloadWorker.enqueue_download(account_handle, project_handle, id)

        assert changeset.changes.args == %{
                 "account_handle" => "test_account",
                 "project_handle" => "test_project",
                 "id" => "test_hash"
               }

        assert changeset.changes.worker == "Cache.S3DownloadWorker"
      end)
    end
  end

  describe "perform/1" do
    test "successfully downloads file from S3 when it exists" do
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(Cache.S3, :exists?, fn ^key -> true end)
      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)
      expect(Cache.Disk, :cas_key, fn ^account_handle, ^project_handle, ^id -> key end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        File.write!(local_path, "test downloaded content")
        {:ok, :done}
      end)

      expect(Cache.Disk, :stat, fn ^account_handle, ^project_handle, ^id ->
        {:ok, %{size: 24}}
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => id
        }
      }

      :telemetry.attach(
        "test-download-handler",
        [:cache, :cas, :download, :success],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      result = S3DownloadWorker.perform(job)

      assert result == :ok
      assert File.exists?(local_path)

      assert_receive {:telemetry_event, [:cache, :cas, :download, :success], %{size: 24},
                      %{
                        cas_id: ^id,
                        account_handle: ^account_handle,
                        project_handle: ^project_handle
                      }}

      :telemetry.detach("test-download-handler")
    end

    test "skips download when file does not exist in S3" do
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"
      key = "test_account/test_project/cas/test_hash"

      expect(Cache.Disk, :cas_key, fn ^account_handle, ^project_handle, ^id -> key end)
      expect(Cache.S3, :exists?, fn ^key -> false end)

      job = %Oban.Job{
        args: %{
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
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"
      key = "test_account/test_project/cas/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(Cache.Disk, :cas_key, fn ^account_handle, ^project_handle, ^id -> key end)
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
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "id" => id
        }
      }

      result = S3DownloadWorker.perform(job)
      assert result == {:error, :timeout}
    end

    test "handles S3 exists? error" do
      account_handle = "test_account"
      project_handle = "test_project"
      id = "test_hash"
      key = "test_account/test_project/cas/test_hash"

      expect(Cache.Disk, :cas_key, fn ^account_handle, ^project_handle, ^id -> key end)
      expect(Cache.S3, :exists?, fn ^key -> false end)

      job = %Oban.Job{
        args: %{
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
