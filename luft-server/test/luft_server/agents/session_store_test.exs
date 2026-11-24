defmodule LuftServer.Agents.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.ObjectStore
  alias Condukt.SessionStore.Snapshot
  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Bucket
  alias LuftServer.Agents.Lease
  alias LuftServer.Agents.Purge
  alias LuftServer.Agents.SessionStore
  alias LuftServer.Repo

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "encrypted snapshot and journal roundtrip fences the previous epoch" do
    id = Ecto.UUID.generate()
    {ObjectStore, old} = SessionStore.store("thread", id, 1)
    {ObjectStore, new} = SessionStore.store("thread", id, 2)
    snapshot = Snapshot.new(%{messages: [Message.user("the secret plan")]})
    message = Message.user("secret step")
    assert :ok = ObjectStore.save(snapshot, old)

    assert :ok =
             ObjectStore.append_journal(
               [{:run_start, 1, %{message: message}}],
               old
             )

    assert {:ok, ^snapshot} = ObjectStore.load(new)
    assert {:ok, [{:run_start, 1, %{message: ^message}}]} = ObjectStore.load_journal(new)
    assert {:error, :fenced} = ObjectStore.append_journal([{:resume, 1, nil}], old)
    {:ok, keys} = Bucket.list([], "agents/thread/#{id}/", nil)
    assert keys != []

    for key <- keys do
      assert {:ok, body} = Bucket.get([], key)
      refute String.contains?(body, "secret")
    end

    assert :ok = SessionStore.delete("thread", id)
    assert {:ok, []} = Bucket.list([], "agents/thread/#{id}/", nil)
  end

  test "bucket creates once, lists literal prefixes in byte order and deletes idempotently" do
    prefix = Ecto.UUID.generate() <> "/%_"
    assert :ok = Bucket.create([], prefix <> "b", "first")
    assert {:error, :exists} = Bucket.create([], prefix <> "b", "replacement")
    assert {:ok, "first"} = Bucket.get([], prefix <> "b")
    assert :ok = Bucket.create([], prefix <> "a", "second")
    assert :ok = Bucket.create([], prefix <> "A", "third")
    assert :ok = Bucket.create([], String.replace(prefix, "%_", "xx") <> "a", "unrelated")
    assert {:ok, [a, b, c]} = Bucket.list([], prefix, nil)
    assert [a, b, c] == Enum.sort([prefix <> "A", prefix <> "a", prefix <> "b"])
    assert {:ok, [^c]} = Bucket.list([], prefix, b)
    assert :ok = Bucket.delete([], c)
    assert :ok = Bucket.delete([], c)
    assert :not_found = Bucket.get([], c)
  end

  test "authenticated ciphertext rejects tampering" do
    {ObjectStore, opts} = SessionStore.store("thread", Ecto.UUID.generate(), 1)
    plaintext = "private journal"
    encrypted = opts[:encrypt].(plaintext)
    assert plaintext == opts[:decrypt].(encrypted)
    <<first, rest::binary>> = encrypted

    assert_raise ArgumentError, fn ->
      opts[:decrypt].(<<Bitwise.bxor(first, 1), rest::binary>>)
    end

    size = byte_size(encrypted) - 1
    head = binary_part(encrypted, 0, size)
    last = :binary.last(encrypted)
    assert_raise ArgumentError, fn -> opts[:decrypt].(<<head::binary, Bitwise.bxor(last, 1)>>) end
    refute encrypted == opts[:encrypt].(plaintext)
  end

  test "purge waits for the grace period then deletes objects before the tombstone" do
    id = Ecto.UUID.generate()
    Lease.want(id, "thread")
    {ObjectStore, opts} = SessionStore.store("thread", id, 1)
    assert :ok = ObjectStore.save(Snapshot.new(%{}), opts)

    Repo.query!(
      "UPDATE agent_sessions SET deleted_at=CURRENT_TIMESTAMP, wanted=false WHERE id=$1",
      [id]
    )

    assert :ok = Purge.run()
    assert {:ok, [_ | _]} = Bucket.list([], "agents/thread/#{id}/", nil)

    Repo.query!(
      "UPDATE agent_sessions SET deleted_at=CURRENT_TIMESTAMP - interval '2 minutes' WHERE id=$1",
      [id]
    )

    assert :ok = Purge.run()
    assert %{rows: []} = Repo.query!("SELECT id FROM agent_sessions WHERE id=$1", [id])
    assert {:ok, []} = Bucket.list([], "agents/thread/#{id}/", nil)
  end
end
