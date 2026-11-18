defmodule Tuist.Agents.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.ObjectStore
  alias Condukt.SessionStore.ObjectStore.Memory
  alias Condukt.SessionStore.Snapshot
  alias Tuist.Agents.SessionStore
  alias Tuist.Agents.TestBucket

  test "stores a session encrypted, refuses an older lease epoch, and deletes it" do
    id = Ecto.UUID.generate()
    {ObjectStore, old} = SessionStore.store("thread", id, 1)
    {ObjectStore, new} = SessionStore.store("thread", id, 2)
    snapshot = Snapshot.new(%{messages: [Message.user("the secret plan")]})

    assert :ok = ObjectStore.save(snapshot, old)
    assert :ok = ObjectStore.append_journal([{:run_start, 1, %{message: Message.user("the secret step")}}], old)
    assert ObjectStore.load(new) == {:ok, snapshot}
    assert ObjectStore.append_journal([{:resume, 1, nil}], old) == {:error, :fenced}

    assert [_ | _] = keys = objects(id)
    refute Enum.any?(keys, &(TestBucket |> Memory.get(&1) |> elem(1) |> String.contains?("secret")))

    assert :ok = SessionStore.delete("thread", id)
    assert objects(id) == []
  end

  defp objects(id) do
    {:ok, keys} = Memory.list(TestBucket, "agents/thread/#{id}/", nil)
    keys
  end
end
