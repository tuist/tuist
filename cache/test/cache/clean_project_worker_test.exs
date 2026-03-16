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
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)
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
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]
      {:ok, renew_calls} = Agent.start_link(fn -> 0 end)

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)

      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff ->
        Agent.update(renew_calls, &(&1 + 1))
        :ok
      end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, ^cutoff ->
        {["keyvalue:test_account:test_project:cas"], 1}
      end)

      expect(Disk, :delete_project_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 4}
      end)

      expect(S3, :delete_objects_with_prefix_before, 2, fn
        "test_account/test_project/", ^cutoff, opts ->
          assert :ok = Keyword.fetch!(opts, :on_progress).()

          case Keyword.fetch!(opts, :type) do
            :xcode_cache -> {:ok, 3}
            :cache -> {:ok, 2}
          end
      end)

      expect(Cleanup, :tombstone_project_entries, fn ^account_handle, ^project_handle, ^cutoff -> 5 end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)

      assert Agent.get(renew_calls, & &1) >= 5
    end

    test "distributed cleanup retries when it loses the cleanup lease" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)

      expect(Cleanup, :renew_project_cleanup_lease, 2, fn ^account_handle, ^project_handle, ^cutoff ->
        send(self(), :renew_called)
        :ok
      end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, ^cutoff ->
        {[], 0}
      end)

      expect(Disk, :delete_project_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:error, :cleanup_lease_lost}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert {:error, :cleanup_lease_lost} = CleanProjectWorker.perform(job)
      end)

      assert_received :renew_called
    end

    test "distributed cleanup uses the safe second-wide cutoff for all cleanup phases" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      account_handle = "test_account"
      project_handle = "test_project"
      cleanup_started_at = ~U[2026-03-12 12:00:00.900000Z]
      safe_cutoff = ~U[2026-03-12 12:00:00Z]

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cleanup_started_at} end)
      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cleanup_started_at -> :ok end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, ^safe_cutoff ->
        {[], 0}
      end)

      expect(Disk, :delete_project_before, fn ^account_handle, ^project_handle, ^safe_cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^safe_cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(Cleanup, :tombstone_project_entries, fn ^account_handle, ^project_handle, ^safe_cutoff -> 0 end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "distributed cleanup fails and skips tombstoning when S3 deletion fails" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      parent = self()
      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)
      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff -> :ok end)

      expect(KeyValueEntries, :delete_project_entries_before, fn ^account_handle, ^project_handle, ^cutoff ->
        {[], 0}
      end)

      expect(Disk, :delete_project_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:error, :timeout}
      end)

      stub(Cleanup, :tombstone_project_entries, fn ^account_handle, ^project_handle, ^cutoff ->
        send(parent, :tombstoned)
        5
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert {:error, :timeout} = CleanProjectWorker.perform(job)
      end)

      refute_received :tombstoned
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
