defmodule Cache.SQLiteBufferTest do
  use ExUnit.Case, async: false

  alias Cache.CacheArtifact
  alias Cache.CacheArtifactsBuffer
  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3TransfersBuffer
  alias Cache.SQLiteBuffer
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    allow_buffer(KeyValueBuffer)
    allow_buffer(CacheArtifactsBuffer)
    allow_buffer(S3TransfersBuffer)

    :ok = KeyValueBuffer.flush()
    :ok = CacheArtifactsBuffer.flush()
    :ok = S3TransfersBuffer.flush()

    Repo.delete_all(S3Transfer)
    Repo.delete_all(CacheArtifact)
    Repo.delete_all(KeyValueEntry)

    :ok
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

    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :cas, key)
    :ok = S3TransfersBuffer.enqueue(:upload, "account", "project", :cas, key)
    :ok = S3TransfersBuffer.flush()

    transfers = Repo.all(S3Transfer)
    assert length(transfers) == 1

    :ok = S3TransfersBuffer.enqueue_delete(hd(transfers).id)
    :ok = S3TransfersBuffer.flush()

    assert Repo.aggregate(S3Transfer, :count, :id) == 0
  end

  test "flushes queued entries on shutdown" do
    key = "keyvalue:shutdown:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "shutdown"}]})

    {:ok, pid} = SQLiteBuffer.start_link(name: :sqlite_buffer_test, buffer_module: KeyValueBuffer)

    Sandbox.allow(Repo, self(), pid)
    true = :ets.insert(:sqlite_buffer_test, {key, %{key: key, json_payload: payload}})

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

    assert %{cas_artifacts: 1} = CacheArtifactsBuffer.queue_stats()

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

    count = Repo.aggregate(KeyValueEntry, :count, :id)
    assert count == 100
  end

  defp allow_buffer(buffer) do
    if pid = Process.whereis(buffer) do
      Sandbox.allow(Repo, self(), pid)
      buffer.reset()
    end
  end
end
