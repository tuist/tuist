defmodule Cache.CASCleanupWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CacheArtifacts
  alias Cache.CAS.Disk, as: CASDisk
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

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes -> [] end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "efgh5678" ->
        "test_account/test_project/cas/ef/gh/efgh5678"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/storage/test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ef/gh/efgh5678" ->
        "/storage/test_account/test_project/cas/ef/gh/efgh5678"
      end)

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

    test "skips S3 and metadata cleanup when disk delete fails" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes -> [] end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/root/protected/file"
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

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes -> [] end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/storage/test_account/test_project/cas/ab/cd/abcd1234"
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

    test "returns :ok even when S3 deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes -> [] end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/storage/test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Config, :cache_bucket, fn -> "test-bucket" end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", ["test_account/test_project/cas/ab/cd/abcd1234"] ->
        %S3{}
      end)

      expect(ExAws, :request, fn %S3{} -> {:error, :timeout} end)

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

    test "skips hashes shorter than 4 characters with warning log" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["ab", "abcd1234"]

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ["abcd1234"] -> [] end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/storage/test_account/test_project/cas/ab/cd/abcd1234"
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

      assert log =~ "Skipping CAS hash shorter than 4 characters"
    end

    test "skips hashes still referenced by other key-value entries" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234", "efgh5678"]

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes ->
        ["efgh5678"]
      end)

      expect(CASDisk, :key, fn ^account_handle, ^project_handle, "abcd1234" ->
        "test_account/test_project/cas/ab/cd/abcd1234"
      end)

      expect(Disk, :artifact_path, fn "test_account/test_project/cas/ab/cd/abcd1234" ->
        "/storage/test_account/test_project/cas/ab/cd/abcd1234"
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

      capture_log(fn ->
        assert :ok = CASCleanupWorker.perform(job)
      end)
    end

    test "skips all cleanup when all hashes are still referenced" do
      account_handle = "test_account"
      project_handle = "test_project"
      cas_hashes = ["abcd1234"]

      expect(KeyValueEntries, :referenced_hashes, fn ^account_handle, ^project_handle, ^cas_hashes ->
        ["abcd1234"]
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
