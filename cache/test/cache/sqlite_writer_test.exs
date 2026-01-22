defmodule Cache.SQLiteWriterTest do
  use ExUnit.Case, async: false

  alias Cache.CacheArtifact
  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.SQLiteWriter
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    if pid = Process.whereis(SQLiteWriter) do
      Sandbox.allow(Repo, self(), pid)
      SQLiteWriter.reset()
    end

    :ok = SQLiteWriter.flush(:all)
    :ok
  end

  test "flush persists key values and keeps latest payload" do
    key = "keyvalue:account:project:cas"
    payload_one = Jason.encode!(%{entries: [%{"value" => "one"}]})
    payload_two = Jason.encode!(%{entries: [%{"value" => "two"}]})

    :ok = SQLiteWriter.enqueue_key_value(key, payload_one)
    :ok = SQLiteWriter.enqueue_key_value(key, payload_two)

    assert %{key_values: 1} = SQLiteWriter.queue_stats()

    :ok = SQLiteWriter.flush(:key_values)

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload_two
  end

  test "flush writes and deletes cas artifacts" do
    key = "account/project/cas/ab/cd/cas1"
    last_accessed_at = DateTime.utc_now()

    :ok = SQLiteWriter.enqueue_cas_access(key, 123, last_accessed_at)
    :ok = SQLiteWriter.flush(:cas_artifacts)

    record = Repo.get_by!(CacheArtifact, key: key)
    assert record.size_bytes == 123

    :ok = SQLiteWriter.enqueue_cas_deletes([key])
    :ok = SQLiteWriter.flush(:cas_artifacts)

    assert Repo.get_by(CacheArtifact, key: key) == nil
  end

  test "flush inserts and deletes s3 transfers with de-duplication" do
    key = "account/project/cas/ab/cd/key"

    :ok = SQLiteWriter.enqueue_s3_transfer(:upload, "account", "project", :cas, key)
    :ok = SQLiteWriter.enqueue_s3_transfer(:upload, "account", "project", :cas, key)
    :ok = SQLiteWriter.flush(:s3_transfers)

    transfers = Repo.all(S3Transfer)
    assert length(transfers) == 1

    :ok = SQLiteWriter.enqueue_s3_transfer_deletes([hd(transfers).id])
    :ok = SQLiteWriter.flush(:s3_transfers)

    assert Repo.aggregate(S3Transfer, :count, :id) == 0
  end

  test "flushes queued entries on shutdown" do
    key = "keyvalue:shutdown:account:project"
    payload = Jason.encode!(%{entries: [%{"value" => "shutdown"}]})

    {:ok, pid} = GenServer.start_link(SQLiteWriter, :ok, [])

    Sandbox.allow(Repo, self(), pid)
    :ok = GenServer.call(pid, {:enqueue, {:key_value, key, payload}})

    :ok = GenServer.stop(pid)

    record = Repo.get_by!(KeyValueEntry, key: key)
    assert record.json_payload == payload
  end
end
