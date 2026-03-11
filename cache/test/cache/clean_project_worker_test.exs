defmodule Cache.CleanProjectWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CleanProjectWorker
  alias Cache.Config
  alias Cache.Disk
  alias Cache.S3

  setup :set_mimic_from_context

  describe "perform/1" do
    test "cleans disk and S3 artifacts from both xcode_cache and cache buckets" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, 2, fn
        "test_account/test_project/", [type: :xcode_cache] -> {:ok, 3}
        "test_account/test_project/", [type: :cache] -> {:ok, 2}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "skips xcode_cache deletion when no dedicated bucket is configured" do
      account_handle = "test_account"
      project_handle = "test_project"

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, 1, fn
        "test_account/test_project/", [type: :cache] -> {:ok, 2}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "logs errors but returns :ok when disk deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> {:error, :eacces} end)

      expect(S3, :delete_all_with_prefix, 2, fn
        "test_account/test_project/", [type: :xcode_cache] -> {:ok, 0}
        "test_account/test_project/", [type: :cache] -> {:ok, 0}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      log =
        capture_log(fn ->
          assert :ok = CleanProjectWorker.perform(job)
        end)

      assert log =~ "Failed to clean disk cache"
    end

    test "logs errors but returns :ok when S3 deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, 2, fn
        "test_account/test_project/", [type: :xcode_cache] -> {:error, :timeout}
        "test_account/test_project/", [type: :cache] -> {:error, :timeout}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      log =
        capture_log(fn ->
          assert :ok = CleanProjectWorker.perform(job)
        end)

      assert log =~ "Failed to clean S3"
    end
  end
end
