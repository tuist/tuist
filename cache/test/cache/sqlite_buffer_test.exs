defmodule Cache.SQLiteBufferTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactsBuffer
  alias Cache.Config
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.KeyValueWriteRepo
  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer
  alias Cache.SQLiteBuffer
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup context do
    :ok = Sandbox.checkout(Repo)
    :ok = Cache.KeyValueRepoTestHelpers.reset!()
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)

    context =
      context
      |> Cache.BufferTestHelpers.setup_key_value_buffer()
      |> Cache.BufferTestHelpers.setup_cache_artifacts_buffer()
      |> Cache.BufferTestHelpers.setup_s3_transfers_buffer()

    :ok = KeyValueBuffer.flush()
    :ok = CacheArtifactsBuffer.flush()
    :ok = S3TransfersBuffer.flush()

    Repo.delete_all(S3Transfer)
    Repo.delete_all(CacheArtifact)
    KeyValueWriteRepo.delete_all(KeyValueEntry)

    {:ok, context}
  end

  test "flush persists key values and keeps latest payload" do
    key = "keyvalue:account:project:cas"
    payload_one = JSON.encode!(%{entries: [%{"value" => "one"}]})
    payload_two = JSON.encode!(%{entries: [%{"value" => "two"}]})

    :ok = KeyValueBuffer.enqueue(key, payload_one)
    :ok = KeyValueBuffer.enqueue(key, payload_two)

    assert %{key_values: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload_two
    assert record.last_accessed_at
  end

  test "distributed writes mark source_updated_at and replication token" do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    key = "keyvalue:account:project:distributed"
    payload = JSON.encode!(%{entries: [%{"value" => "value"}]})

    :ok = KeyValueBuffer.enqueue(key, payload)
    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.source_updated_at
    assert record.replication_enqueued_at
  end

  test "local writes clear distributed replication fields" do
    key = "keyvalue:account:project:local"
    payload = Jason.encode!(%{entries: [%{"value" => "value"}]})
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)
    distributed_time = DateTime.add(DateTime.utc_now(), -120, :second)

    KeyValueWriteRepo.insert!(%KeyValueEntry{
      key: key,
      json_payload: Jason.encode!(%{entries: [%{"value" => "old"}]}),
      last_accessed_at: distributed_time,
      source_updated_at: distributed_time,
      replication_enqueued_at: distributed_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    :ok = KeyValueBuffer.enqueue(key, payload)
    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
    assert is_nil(record.source_updated_at)
    assert is_nil(record.replication_enqueued_at)
  end

  test "access-only entry updates last_accessed_at without changing payload" do
    key = "keyvalue:access-only:account:project"
    payload = JSON.encode!(%{entries: [%{"value" => "original"}]})

    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    KeyValueWriteRepo.insert!(%KeyValueEntry{
      key: key,
      json_payload: payload,
      last_accessed_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
    assert DateTime.compare(record.last_accessed_at, initial_time) != :lt
  end

  test "distributed access updates replication token only for shared-lineage rows" do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    legacy_key = "keyvalue:legacy:account:project"
    shared_key = "keyvalue:shared:account:project"
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)
    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)

    KeyValueWriteRepo.insert!(%KeyValueEntry{
      key: legacy_key,
      json_payload: JSON.encode!(%{entries: []}),
      last_accessed_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    KeyValueWriteRepo.insert!(%KeyValueEntry{
      key: shared_key,
      json_payload: JSON.encode!(%{entries: []}),
      last_accessed_at: initial_time,
      source_updated_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    :ok = KeyValueBuffer.enqueue_access(legacy_key)
    :ok = KeyValueBuffer.enqueue_access(shared_key)
    :ok = KeyValueBuffer.flush()

    legacy_record = KeyValueRepo.get_by!(KeyValueEntry, key: legacy_key)
    shared_record = KeyValueRepo.get_by!(KeyValueEntry, key: shared_key)

    assert is_nil(legacy_record.replication_enqueued_at)
    assert shared_record.replication_enqueued_at
  end

  test "local access does not enqueue replication for legacy shared rows" do
    key = "keyvalue:shared:account:project"
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)
    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)

    KeyValueWriteRepo.insert!(%KeyValueEntry{
      key: key,
      json_payload: Jason.encode!(%{entries: []}),
      last_accessed_at: initial_time,
      source_updated_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert is_nil(record.replication_enqueued_at)
  end

  test "flush handles access batches at sqlite parameter limits" do
    base_key = "keyvalue:batch-access-limit:account:project"
    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for i <- 1..1000 do
        %{
          key: "#{base_key}:#{i}",
          json_payload: JSON.encode!(%{entries: [%{"value" => "hash-#{i}"}]}),
          last_accessed_at: initial_time,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    {1000, _} = KeyValueWriteRepo.insert_all(KeyValueEntry, rows)

    for i <- 1..1000 do
      :ok = KeyValueBuffer.enqueue_access("#{base_key}:#{i}")
    end

    :ok = KeyValueBuffer.flush()

    refreshed_count =
      KeyValueRepo.aggregate(
        from(entry in KeyValueEntry,
          where: like(entry.key, ^"#{base_key}:%") and entry.last_accessed_at > ^initial_time
        ),
        :count,
        :id
      )

    assert refreshed_count == 1000
  end

  test "multiple accesses for same key are de-duplicated in queue" do
    key = "keyvalue:access-dedup:account:project"
    write_key = "keyvalue:access-dedup:write"

    :ok = KeyValueBuffer.enqueue(write_key, JSON.encode!(%{value: "write"}))
    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.enqueue_access(key)

    assert %{key_values: 2, total: 2} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()
  end

  test "flush writes and deletes cache artifacts" do
    key = "account/project/xcode/ab/cd/cas1"
    last_accessed_at = DateTime.utc_now()

    :ok = CacheArtifactsBuffer.enqueue_access(key, 123, last_accessed_at)
    :ok = CacheArtifactsBuffer.flush()

    record = Repo.get_by!(CacheArtifact, key: key)
    assert record.size_bytes == 123

    :ok = CacheArtifactsBuffer.enqueue_delete(key)
    :ok = CacheArtifactsBuffer.flush()

    assert Repo.get_by(CacheArtifact, key: key) == nil
  end

  test "flush inserts and deletes s3 transfers with de-duplication" do
    key = "account/project/xcode/ab/cd/key"

    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :xcode_cache, key)
    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :xcode_cache, key)
    :ok = S3TransfersBuffer.flush()

    transfers = Repo.all(from(transfer in S3Transfer, where: transfer.key == ^key))
    assert length(transfers) == 1

    :ok = S3TransfersBuffer.enqueue_delete(hd(transfers).id)
    :ok = S3TransfersBuffer.flush()

    assert Repo.aggregate(from(transfer in S3Transfer, where: transfer.key == ^key), :count, :id) == 0
  end

  test "flushes queued entries on shutdown" do
    key = "keyvalue:shutdown:account:project"
    payload = JSON.encode!(%{entries: [%{"value" => "shutdown"}]})

    suffix = :erlang.unique_integer([:positive])
    shutdown_buf = :"sqlite_buffer_shutdown_test_#{suffix}"
    {:ok, pid} = SQLiteBuffer.start_link(name: shutdown_buf, buffer_module: KeyValueBuffer)

    true = :ets.insert(shutdown_buf, {key, {:write, %{key: key, json_payload: payload}}})

    :ok = GenServer.stop(pid)

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
  end

  test "unexpected info messages are logged and ignored" do
    key = "keyvalue:unexpected-message:account:project"
    payload = JSON.encode!(%{entries: [%{"value" => "unexpected"}]})

    suffix = :erlang.unique_integer([:positive])
    buffer = :"sqlite_buffer_unexpected_message_test_#{suffix}"
    {:ok, pid} = SQLiteBuffer.start_link(name: buffer, buffer_module: KeyValueBuffer)

    log =
      capture_log(fn ->
        send(pid, {[:alias | make_ref()], :dropped})
        true = :ets.insert(buffer, {key, {:write, %{key: key, json_payload: payload}}})
        :ok = SQLiteBuffer.flush(buffer)
      end)

    assert log =~ "key_values buffer received unexpected message"

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload

    :ok = GenServer.stop(pid)
  end

  test "concurrent writes to the same key preserve last value" do
    key = "keyvalue:concurrent:account:project"

    tasks =
      for i <- 1..100 do
        Task.async(fn ->
          payload = JSON.encode!(%{value: i})
          KeyValueBuffer.enqueue(key, payload)
        end)
      end

    Task.await_many(tasks)

    assert %{key_values: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    decoded = JSON.decode!(record.json_payload)
    assert decoded["value"] in 1..100
  end

  test "concurrent access and delete for same key preserves last operation" do
    key = "account/project/xcode/ab/cd/concurrent"
    last_accessed_at = DateTime.utc_now()

    tasks =
      for i <- 1..100 do
        Task.async(fn ->
          if rem(i, 2) == 0 do
            CacheArtifactsBuffer.enqueue_access(key, i * 100, last_accessed_at)
          else
            CacheArtifactsBuffer.enqueue_delete(key)
          end
        end)
      end

    Task.await_many(tasks)

    assert %{cache_artifacts: 1} = CacheArtifactsBuffer.queue_stats()

    :ok = CacheArtifactsBuffer.flush()

    case Repo.get_by(CacheArtifact, key: key) do
      nil ->
        assert true

      record ->
        assert rem(record.size_bytes, 100) == 0
    end
  end

  test "writes during flush are not lost" do
    import Ecto.Query

    base_key = "keyvalue:during_flush:account:project"

    for i <- 1..50 do
      KeyValueBuffer.enqueue("#{base_key}:#{i}", JSON.encode!(%{batch: "first", index: i}))
    end

    flush_task = Task.async(fn -> KeyValueBuffer.flush() end)

    for i <- 51..100 do
      KeyValueBuffer.enqueue("#{base_key}:#{i}", JSON.encode!(%{batch: "second", index: i}))
    end

    Task.await(flush_task)

    :ok = KeyValueBuffer.flush()

    count = KeyValueRepo.aggregate(from(e in KeyValueEntry, where: like(e.key, ^"#{base_key}%")), :count, :id)
    assert count == 100
  end
end
