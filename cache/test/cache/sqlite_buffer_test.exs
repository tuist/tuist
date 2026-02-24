defmodule Cache.SQLiteBufferTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactsBuffer
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer
  alias Cache.SQLiteBuffer
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Repo)

    suffix = :erlang.unique_integer([:positive])

    kv_name = :"kv_buf_test_#{suffix}"
    ca_name = :"ca_buf_test_#{suffix}"
    s3_name = :"s3_buf_test_#{suffix}"

    kv_pid = start_supervised!({SQLiteBuffer, [name: kv_name, buffer_module: KeyValueBuffer]})
    ca_pid = start_supervised!({SQLiteBuffer, [name: ca_name, buffer_module: CacheArtifactsBuffer]}, id: ca_name)
    s3_pid = start_supervised!({SQLiteBuffer, [name: s3_name, buffer_module: S3TransfersBuffer]}, id: s3_name)

    Sandbox.allow(Repo, self(), kv_pid)
    Sandbox.allow(Repo, self(), ca_pid)
    Sandbox.allow(Repo, self(), s3_pid)

    stub(KeyValueBuffer, :enqueue, fn key, json_payload ->
      entry = %{key: key, json_payload: json_payload}
      true = :ets.insert(kv_name, {key, {:write, entry}})
      :ok
    end)

    stub(KeyValueBuffer, :enqueue_access, fn key ->
      entry = %{key: key}
      _inserted? = :ets.insert_new(kv_name, {key, {:access, entry}})
      :ok
    end)

    stub(KeyValueBuffer, :flush, fn -> SQLiteBuffer.flush(kv_name) end)
    stub(KeyValueBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(kv_name) end)
    stub(KeyValueBuffer, :reset, fn -> SQLiteBuffer.reset(kv_name) end)

    stub(CacheArtifactsBuffer, :enqueue_access, fn key, size_bytes, last_accessed_at ->
      entry = %{key: key, size_bytes: size_bytes, last_accessed_at: last_accessed_at}
      true = :ets.insert(ca_name, {key, {:access, entry}})
      :ok
    end)

    stub(CacheArtifactsBuffer, :enqueue_delete, fn key ->
      true = :ets.insert(ca_name, {key, :delete})
      :ok
    end)

    stub(CacheArtifactsBuffer, :flush, fn -> SQLiteBuffer.flush(ca_name) end)
    stub(CacheArtifactsBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(ca_name) end)
    stub(CacheArtifactsBuffer, :reset, fn -> SQLiteBuffer.reset(ca_name) end)

    stub(S3TransfersBuffer, :enqueue, fn type, account_handle, project_handle, artifact_type, key ->
      entry = %{
        id: UUIDv7.generate(),
        type: type,
        account_handle: account_handle,
        project_handle: project_handle,
        artifact_type: artifact_type,
        key: key,
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      true = :ets.insert(s3_name, {{:insert, type, key}, entry})
      :ok
    end)

    stub(S3TransfersBuffer, :enqueue_delete, fn id ->
      true = :ets.insert(s3_name, {{:delete, id}, :delete})
      :ok
    end)

    stub(S3TransfersBuffer, :flush, fn -> SQLiteBuffer.flush(s3_name) end)
    stub(S3TransfersBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(s3_name) end)
    stub(S3TransfersBuffer, :reset, fn -> SQLiteBuffer.reset(s3_name) end)

    {:ok, kv_name: kv_name, ca_name: ca_name, s3_name: s3_name}
  end

  test "flush persists key values and keeps latest payload" do
    key = "keyvalue:account:project:cas"
    payload_one = Jason.encode!(%{entries: [%{"value" => "one"}]})
    payload_two = Jason.encode!(%{entries: [%{"value" => "two"}]})

    :ok = KeyValueBuffer.enqueue(key, payload_one)
    :ok = KeyValueBuffer.enqueue(key, payload_two)

    assert %{key_values: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload_two
    assert record.last_accessed_at
  end

  test "write then access for same key keeps pending write" do
    key = "keyvalue:write-then-access:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "write"}]})

    :ok = KeyValueBuffer.enqueue(key, payload)
    :ok = KeyValueBuffer.enqueue_access(key)

    assert %{key_values: 1, total: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
    assert record.last_accessed_at
  end

  test "access-only entry updates last_accessed_at without changing payload" do
    key = "keyvalue:access-only:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "original"}]})

    initial_time = DateTime.add(DateTime.utc_now(), -120, :second)
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%KeyValueEntry{
      key: key,
      json_payload: payload,
      last_accessed_at: initial_time,
      inserted_at: timestamp,
      updated_at: timestamp
    })

    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.flush()

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
    assert DateTime.after?(record.last_accessed_at, initial_time)
  end

  test "multiple accesses for same key are de-duplicated in queue" do
    key = "keyvalue:access-dedup:account:project"
    write_key = "keyvalue:access-dedup:write"

    :ok = KeyValueBuffer.enqueue(write_key, Jason.encode!(%{value: "write"}))
    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.enqueue_access(key)
    :ok = KeyValueBuffer.enqueue_access(key)

    assert %{key_values: 2, total: 2} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()
  end

  test "flush writes and deletes cas artifacts" do
    key = "account/project/cas/ab/cd/cas1"
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
    key = "account/project/cas/ab/cd/key"

    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :xcode_cas, key)
    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :xcode_cas, key)
    :ok = S3TransfersBuffer.flush()

    import Ecto.Query
    transfers = Repo.all(from(t in S3Transfer, where: t.key == ^key))
    assert length(transfers) == 1

    :ok = S3TransfersBuffer.enqueue_delete(hd(transfers).id)
    :ok = S3TransfersBuffer.flush()

    assert Repo.aggregate(from(t in S3Transfer, where: t.key == ^key), :count, :id) == 0
  end

  test "flushes queued entries on shutdown" do
    key = "keyvalue:shutdown:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "shutdown"}]})

    suffix = :erlang.unique_integer([:positive])
    shutdown_buf = :"sqlite_buffer_shutdown_test_#{suffix}"
    {:ok, pid} = SQLiteBuffer.start_link(name: shutdown_buf, buffer_module: KeyValueBuffer)

    Sandbox.allow(Repo, self(), pid)
    true = :ets.insert(shutdown_buf, {key, {:write, %{key: key, json_payload: payload}}})

    :ok = GenServer.stop(pid)

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
  end

  test "concurrent writes to the same key preserve last value" do
    key = "keyvalue:concurrent:account:project"

    tasks =
      for i <- 1..100 do
        Task.async(fn ->
          payload = Jason.encode!(%{value: i})
          KeyValueBuffer.enqueue(key, payload)
        end)
      end

    Task.await_many(tasks)

    assert %{key_values: 1} = KeyValueBuffer.queue_stats()

    :ok = KeyValueBuffer.flush()

    record = Repo.get_by!(KeyValueEntry, key: key)
    decoded = Jason.decode!(record.json_payload)
    assert decoded["value"] in 1..100
  end

  test "concurrent access and delete for same key preserves last operation" do
    key = "account/project/cas/ab/cd/concurrent"
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
    base_key = "keyvalue:during_flush:account:project"

    for i <- 1..50 do
      KeyValueBuffer.enqueue("#{base_key}:#{i}", Jason.encode!(%{batch: "first", index: i}))
    end

    flush_task = Task.async(fn -> KeyValueBuffer.flush() end)

    for i <- 51..100 do
      KeyValueBuffer.enqueue("#{base_key}:#{i}", Jason.encode!(%{batch: "second", index: i}))
    end

    Task.await(flush_task)

    :ok = KeyValueBuffer.flush()

    import Ecto.Query
    count = Repo.aggregate(from(e in KeyValueEntry, where: like(e.key, ^"#{base_key}%")), :count, :id)
    assert count == 100
  end
end
