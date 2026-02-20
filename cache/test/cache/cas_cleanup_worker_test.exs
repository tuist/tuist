defmodule Cache.CASCleanupWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CacheArtifacts
  alias Cache.CAS
  alias Cache.CASCleanupWorker
  alias Cache.Config
  alias Cache.Disk
  alias Cache.KeyValueEntries
  alias ExAws.Operation.S3

  describe "perform/1" do
    test "deletes CAS artifacts from disk, S3, and metadata" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234", "efgh5678"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        cas_hashes
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "efgh5678" ->
        "test_account/test_project/cas/ef/gh/efgh5678"
      end)

      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ab/cd/abcd1234" -> :ok end)
      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ef/gh/efgh5678" -> :ok end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket",
                                                    [
                                                      "test_account/test_project/cas/ab/cd/abcd1234",
                                                      "test_account/test_project/cas/ef/gh/efgh5678"
                                                    ] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:ok, %{}} end)

      expect(CacheArtifacts, :delete_by_keys, fn [
                                                   "test_account/test_project/cas/ab/cd/abcd1234",
                                                   "test_account/test_project/cas/ef/gh/efgh5678"
                                                 ] ->
        :ok
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      capture_log(fn ->
        assert :ok = CASCleanupWorker.perform(job)
      end)
    end

    test "logs disk failure but still proceeds with S3 and metadata cleanup" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        cas_hashes
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        {:error, :eacces}
      end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:ok, %{}} end)

      expect(CacheArtifacts, :delete_by_keys, fn ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        :ok
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      log =
        capture_log(fn ->
          assert :ok = CASCleanupWorker.perform(job)
        end)

      assert log =~ "Failed to delete CAS artifact"
    end

    test "treats :enoent as successful disk cleanup and proceeds with S3 and metadata" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        cas_hashes
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        {:error, :enoent}
      end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:ok, %{}} end)

      expect(CacheArtifacts, :delete_by_keys, fn ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        :ok
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      log =
        capture_log(fn ->
          assert :ok = CASCleanupWorker.perform(job)
        end)

      refute log =~ "Failed to delete CAS artifact"
    end

    test "skips metadata cleanup when S3 deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        cas_hashes
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ab/cd/abcd1234" -> :ok end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:error, :timeout} end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      log =
        capture_log(fn ->
          assert :ok = CASCleanupWorker.perform(job)
        end)

      assert log =~ "Failed to delete S3 objects"
    end

    test "handles empty cas_hashes gracefully" do
      account_handle = "test_account"
      project_handle = "test_project"

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => []
        }
      }

      capture_log(fn ->
        assert :ok = CASCleanupWorker.perform(job)
      end)
    end

    test "skips hashes still referenced by other key-value entries" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234", "efgh5678"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        ["abcd1234"]
      end)

      expect(CAS.Disk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :delete_artifact, fn "test_account/test_project/cas/ab/cd/abcd1234" -> :ok end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:ok, %{}} end)

      expect(CacheArtifacts, :delete_by_keys, fn ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        :ok
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      capture_log(fn ->
        assert :ok = CASCleanupWorker.perform(job)
      end)
    end

    test "skips all cleanup when all hashes are still referenced" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :unreferenced_hashes, fn ^cas_hashes, ^account_handle, ^project_handle ->
        []
      end)

      job = %Oban.Job{
        args: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "cas_hashes" => cas_hashes
        }
      }

      capture_log(fn ->
        assert :ok = CASCleanupWorker.perform(job)
      end)
    end
  end
end
