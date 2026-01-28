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

    :ok = CacheArtifactsBuffer.enqueue_deletes([key])
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

    :ok = S3TransfersBuffer.enqueue_deletes([hd(transfers).id])
    :ok = S3TransfersBuffer.flush()

    assert Repo.aggregate(S3Transfer, :count, :id) == 0
  end

  test "flushes queued entries on shutdown" do
    key = "keyvalue:shutdown:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "shutdown"}]})

    {:ok, pid} = SQLiteBuffer.start_link(name: :sqlite_buffer_test, buffer_module: KeyValueBuffer)

    Sandbox.allow(Repo, self(), pid)
    :ok = GenServer.call(pid, {:enqueue, {:key_value, key, payload}})

    :ok = GenServer.stop(pid)

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
  end

  defp allow_buffer(buffer) do
    if pid = Process.whereis(buffer) do
      Sandbox.allow(Repo, self(), pid)
      buffer.reset()
    end
  end
end
