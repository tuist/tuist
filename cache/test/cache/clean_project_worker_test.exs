defmodule Cache.CleanProjectWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CacheArtifacts
  alias Cache.CleanProjectWorker
  alias Cache.Config
  alias Cache.Disk
  alias Cache.DistributedKV.Cleanup
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.KeyValueStore
  alias Cache.S3
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(KeyValueRepo)
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)
    stub(Cleanup, :expire_project_cleanup_lease, fn _account_handle, _project_handle, _cleanup_started_at -> :ok end)
    stub(Cleanup, :put_local_applied_generation, fn _account_handle, _project_handle, _generation -> :ok end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)
    stub(KeyValueAccessTracker, :shared_lineage?, fn _key -> false end)
    stub(KeyValueAccessTracker, :allow_access_bump?, fn _key -> false end)
    stub(CacheArtifacts, :delete_by_keys, fn _keys -> :ok end)
    stub(CacheArtifacts, :delete_by_project, fn _account_handle, _project_handle -> :ok end)
    :ok
  end

  describe "perform/1" do
    test "cleans local disk and S3 artifacts" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, %DateTime{}, opts ->
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          refute Keyword.has_key?(opts, :include_pending)
          {[], 0}
      end)

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)
      expect(CacheArtifacts, :delete_by_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, 2, fn
        "test_account/test_project/", [type: :xcode_cache] -> {:ok, 3}
        "test_account/test_project/", [type: :cache] -> {:ok, 2}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "distributed cleanup uses cutoff-aware helpers and publishes cleanup" do
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

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {["keyvalue:test_account:test_project:cas"], 1}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
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

      expect(Cleanup, :publish_project_cleanup, fn ^account_handle, ^project_handle, ^cutoff ->
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      expect(Cleanup, :put_local_applied_generation, fn ^account_handle, ^project_handle, 1 -> :ok end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)

      assert Agent.get(renew_calls, & &1) >= 5
    end

    test "distributed cleanup keeps a published cleanup successful when local applied-generation bookkeeping fails" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)
      stub(Config, :xcode_cache_bucket, fn -> nil end)

      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)
      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff -> :ok end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {[], 0}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(Cleanup, :publish_project_cleanup, fn ^account_handle, ^project_handle, ^cutoff ->
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      expect(Cleanup, :put_local_applied_generation, fn ^account_handle, ^project_handle, 1 ->
        raise "local state write failed"
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      log =
        capture_log(fn ->
          assert :ok = CleanProjectWorker.perform(job)
        end)

      assert log =~ "Distributed cleanup was already published for #{account_handle}/#{project_handle}"
      assert log =~ "persisting the local applied generation failed"
    end

    test "distributed cleanup retries when it loses the cleanup lease" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)

      expect(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff ->
        send(self(), :renew_called)
        :ok
      end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {[], 0}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
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

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^safe_cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {[], 0}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^safe_cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^safe_cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(Cleanup, :publish_project_cleanup, fn ^account_handle, ^project_handle, ^cleanup_started_at ->
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "distributed cleanup still performs node-local cleanup while shared cleanup is already in progress" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)
      stub(Config, :xcode_cache_bucket, fn -> nil end)

      account_handle = "test_account"
      project_handle = "test_project"
      cleanup_cutoff = ~U[2026-03-12 12:00:00Z]
      parent = self()

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle ->
        {:error, :cleanup_already_in_progress}
      end)

      expect(Cleanup, :latest_project_cleanup_cutoff, fn ^account_handle, ^project_handle -> cleanup_cutoff end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cleanup_cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          send(parent, :kv_deleted)
          {[], 0}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cleanup_cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
        send(parent, :disk_deleted)
        {:ok, 0}
      end)

      stub(S3, :delete_objects_with_prefix_before, fn _prefix, _cutoff, _opts ->
        send(parent, :shared_s3_deleted)
        {:ok, 0}
      end)

      stub(Cleanup, :publish_project_cleanup, fn _account_handle, _project_handle, _cutoff ->
        send(parent, :published)
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)

      assert_received :kv_deleted
      assert_received :disk_deleted
      refute_received :shared_s3_deleted
      refute_received :published
    end

    test "distributed cleanup keeps active lease conflicts retryable on retry attempts after local cleanup" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)
      stub(Config, :xcode_cache_bucket, fn -> nil end)

      account_handle = "test_account"
      project_handle = "test_project"
      cleanup_cutoff = ~U[2026-03-12 12:00:00Z]
      parent = self()

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle ->
        {:error, :cleanup_already_in_progress}
      end)

      expect(Cleanup, :latest_project_cleanup_cutoff, fn ^account_handle, ^project_handle -> cleanup_cutoff end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cleanup_cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          send(parent, :kv_deleted)
          {[], 0}
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cleanup_cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
        send(parent, :disk_deleted)
        {:ok, 0}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}, attempt: 2}

      capture_log(fn ->
        assert {:error, :cleanup_already_in_progress} = CleanProjectWorker.perform(job)
      end)

      assert_received :kv_deleted
      assert_received :disk_deleted
    end

    test "distributed cleanup propagates local KV cleanup lease-loss errors" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      account_handle = "test_account"
      project_handle = "test_project"
      cleanup_cutoff = ~U[2026-03-12 12:00:00Z]

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cleanup_cutoff} end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cleanup_cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {:error, :cleanup_lease_lost}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert {:error, :cleanup_lease_lost} = CleanProjectWorker.perform(job)
      end)
    end

    test "distributed cleanup fails and skips publication when S3 deletion fails" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      parent = self()
      account_handle = "test_account"
      project_handle = "test_project"
      cutoff = ~U[2026-03-12 12:00:00Z]

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cutoff} end)
      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff -> :ok end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, ^cutoff, opts ->
          assert Keyword.fetch!(opts, :include_pending) == true
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          {[], 0}
      end)

      expect(Cleanup, :expire_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cutoff ->
        :ok
      end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:error, :timeout}
      end)

      stub(Cleanup, :publish_project_cleanup, fn ^account_handle, ^project_handle, ^cutoff ->
        send(parent, :published)
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert {:error, :timeout} = CleanProjectWorker.perform(job)
      end)

      refute_received :published
    end

    test "skips xcode_cache deletion when no dedicated bucket is configured" do
      account_handle = "test_account"
      project_handle = "test_project"

      stub(Config, :xcode_cache_bucket, fn -> nil end)

      expect(KeyValueEntries, :delete_project_entries_before, fn
        ^account_handle, ^project_handle, %DateTime{}, opts ->
          assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
          assert is_function(Keyword.fetch!(opts, :after_delete_batch), 1)
          refute Keyword.has_key?(opts, :include_pending)
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

    test "distributed cleanup removes pending local rows before an immediate same-node read" do
      stub(Config, :key_value_mode, fn -> :distributed end)
      stub(Config, :distributed_kv_enabled?, fn -> true end)
      stub(Config, :xcode_cache_bucket, fn -> nil end)

      account_handle = "test_account"
      project_handle = "test_project"
      cas_id = "pending"
      cleanup_started_at = ~U[2026-03-12 12:00:00.900000Z]
      safe_cutoff = ~U[2026-03-12 12:00:00Z]
      row_source_updated_at = ~U[2026-03-12 12:00:00.000000Z]
      replication_enqueued_at = ~U[2026-03-12 12:00:01.000000Z]
      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      stale_payload = Jason.encode!(%{entries: [%{"value" => "stale"}]})

      KeyValueRepo.insert!(%KeyValueEntry{
        key: key,
        json_payload: stale_payload,
        source_node: "test-node",
        last_accessed_at: replication_enqueued_at,
        source_updated_at: row_source_updated_at,
        replication_enqueued_at: replication_enqueued_at
      })

      assert {:ok, true} = Cachex.put(:cache_keyvalue_store, key, stale_payload)

      expect(Cleanup, :begin_project_cleanup, fn ^account_handle, ^project_handle -> {:ok, cleanup_started_at} end)
      stub(Cleanup, :renew_project_cleanup_lease, fn ^account_handle, ^project_handle, ^cleanup_started_at -> :ok end)

      expect(Disk, :delete_project_files_before, fn ^account_handle, ^project_handle, ^safe_cutoff, opts ->
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        assert is_function(Keyword.fetch!(opts, :on_deleted_keys), 1)
        {:ok, 0}
      end)

      expect(S3, :delete_objects_with_prefix_before, fn "test_account/test_project/", ^safe_cutoff, opts ->
        assert Keyword.fetch!(opts, :type) == :cache
        assert :ok = Keyword.fetch!(opts, :on_progress).()
        {:ok, 0}
      end)

      expect(Cleanup, :publish_project_cleanup, fn ^account_handle, ^project_handle, ^cleanup_started_at ->
        {:ok, %{published_cleanup_generation: 1, cleanup_event_id: 1}}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)

      assert KeyValueRepo.get_by(KeyValueEntry, key: key) == nil
      assert {:ok, nil} = Cachex.get(:cache_keyvalue_store, key)
      assert {:error, :not_found} = KeyValueStore.get_key_value(cas_id, account_handle, project_handle)
    end
  end
end
