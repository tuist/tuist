defmodule Cache.CleanProjectWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CleanProjectWorker
  alias Cache.Config
  alias Cache.Disk
  alias Cache.DistributedKV.Cleanup
  alias Cache.KeyValueEntries
  alias Cache.S3

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :key_value_mode, :local)
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)
    :ok
  end

  describe "perform/1" do
    test "cleans local disk and S3 artifacts" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, %DateTime{} ->
        {[], 0}
      end)

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

    test "distributed cleanup uses cutoff-aware helpers and tombstones" do
      Application.put_env(:cache, :key_value_mode, :distributed)

      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = DateTime.utc_now()

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, ^cutoff ->
        {["keyvalue:test_account:test_project:cas"], 1}
      end)

      expect(Disk, :delete_project_before, fn ^account_handle, ^project_handle, ^cutoff -> {:ok, 4} end)

      expect(S3, :delete_objects_with_prefix_before, 2, fn
        "test_account/test_project/", ^cutoff, [type: :xcode_cache] -> {:ok, 3}
        "test_account/test_project/", ^cutoff, [type: :cache] -> {:ok, 2}
      end)

      expect(Cleanup, :tombstone_project_entries, fn ^account_handle, ^project_handle, ^cutoff -> 5 end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "skips xcode_cache deletion when no dedicated bucket is configured" do
      account_handle = "test_account"
      project_handle = "test_project"

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, %DateTime{} ->
        {[], 0}
      end)

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, 1, fn
        "test_account/test_project/", [type: :cache] -> {:ok, 2}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end
  end
end
