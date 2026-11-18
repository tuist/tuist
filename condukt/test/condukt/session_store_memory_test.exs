defmodule Condukt.SessionStore.MemoryTest do
  use ExUnit.Case, async: true
  use Condukt.SessionStore.Conformance, store: Condukt.SessionStore.Memory

  alias Condukt.Message
  alias Condukt.SessionStore.Memory
  alias Condukt.SessionStore.Snapshot

  setup do
    ref = make_ref()
    %{store_opts: [key: {ref, :a}], other_store_opts: [key: {ref, :b}]}
  end

  test "saves, loads, and clears snapshots" do
    key = make_ref()

    snapshot = %Snapshot{
      messages: [Message.user("hello"), Message.assistant("world")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "stored prompt"
    }

    assert Memory.load(key: key) == :not_found
    assert :ok = Memory.save(snapshot, key: key)
    assert {:ok, ^snapshot} = Memory.load(key: key)
    assert :ok = Memory.clear(key: key)
    assert Memory.load(key: key) == :not_found
  end
end
