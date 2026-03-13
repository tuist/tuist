defmodule Cache.SQLiteBufferTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactsBuffer
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer
  alias Cache.SQLiteBuffer
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup context do
    :ok = Sandbox.checkout(Repo)
    :ok = Sandbox.checkout(KeyValueRepo)
    Application.put_env(:cache, :key_value_mode, :local)
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)

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
    KeyValueRepo.delete_all(KeyValueEntry)

    {:ok, context}
  end

  test "flush persists key values and keeps latest payload" do
    key = "keyvalue:account:project:cas"
    payload_one = Jason.encode!(%{entries: [%{"value" => "one"}]})
    payload_two = Jason.encode!(%{entries: [%{"value" => "two"}]})

    :ok = KeyValueBuffer.enqueue(key, payload_one)
    :ok = KeyValueBuffer.enqueue(key, payload_two)

    assert %{key_values: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload_two
    assert record.last_accessed_at
  end

  test "distributed writes mark source_updated_at and replication token" do
    Application.put_env(:cache, :key_value_mode, :distributed)

    key = "keyvalue:account:project:distributed"
    payload = Jason.encode!(%{entries: [%{"value" => "value"}]})

    :ok = KeyValueBuffer.enqueue(key, payload)
    :ok = KeyValueBuffer.flush()

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.source_updated_at
    assert record.replication_enqueued_at

    Application.put_env(:cache, :key_value_mode, :local)
  end

  test "access-only entry updates last_accessed_at without changing payload" do
    key = "keyvalue:access-only:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "original"}]})

    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    KeyValueRepo.insert!(%KeyValueEntry{
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
    Application.put_env(:cache, :key_value_mode, :distributed)

    legacy_key = "keyvalue:legacy:account:project"
    shared_key = "keyvalue:shared:account:project"
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)
    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: legacy_key,
      json_payload: Jason.encode!(%{entries: []}),
      last_accessed_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: shared_key,
      json_payload: Jason.encode!(%{entries: []}),
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

    Application.put_env(:cache, :key_value_mode, :local)
  end

  test "flush handles access batches at sqlite parameter limits" do
    base_key = "keyvalue:batch-access-limit:account:project"
    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for i <- 1..1000 do
        %{
          key: "#{base_key}:#{i}",
          json_payload: Jason.encode!(%{entries: [%{"value" => "hash-#{i}"}]}),
          last_accessed_at: initial_time,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    {1000, _} = KeyValueRepo.insert_all(KeyValueEntry, rows)

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
    payload = Jason.encode!(%{entries: [%{"value" => "shutdown"}]})

    suffix = :erlang.unique_integer([:positive])
    shutdown_buf = :"sqlite_buffer_shutdown_test_#{suffix}"
    {:ok, pid} = SQLiteBuffer.start_link(name: shutdown_buf, buffer_module: KeyValueBuffer)

    Sandbox.allow(KeyValueRepo, self(), pid)
    true = :ets.insert(shutdown_buf, {key, {:write, %{key: key, json_payload: payload}}})

    :ok = GenServer.stop(pid)

    record = KeyValueRepo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
  end
end
