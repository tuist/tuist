defmodule Atlas.MCP.Tools.MemoryToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.RecallMemory
  alias Atlas.MCP.Tools.SaveMemory
  alias Atlas.Memory

  describe "save_memory" do
    test "saves a memory and returns its identity" do
      assert {:ok, payload} = execute_tool(SaveMemory, nil, %{"kind" => "fact", "body" => "Acme renews in Q3 2026."})

      assert payload.saved
      assert payload.memory.kind == "fact"
      assert is_binary(payload.memory.id)
      assert is_float(payload.memory.importance)
    end

    test "honors an explicit importance" do
      args = %{"kind" => "decision", "body" => "Acme deal needs legal review.", "importance" => 0.9}

      assert {:ok, payload} = execute_tool(SaveMemory, nil, args)
      assert payload.memory.importance == 0.9
    end

    test "rejects an unknown kind" do
      assert {:error, message} = execute_tool(SaveMemory, nil, %{"kind" => "nonsense", "body" => "Something."})
      assert message =~ "kind must be one of"
    end
  end

  describe "recall_memory" do
    test "returns matching memories" do
      {:ok, _node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
      {:ok, _node} = Memory.create_node(%{kind: :preference, body: "Pat prefers Loom over Zoom."})

      assert {:ok, payload} = execute_tool(RecallMemory, nil, %{"query" => "Acme renewal"})

      assert payload.memory_count == length(payload.memories)
      assert Enum.any?(payload.memories, &(&1.body =~ "Acme"))
      refute Enum.any?(payload.memories, &(&1.body =~ "Loom"))
    end

    test "returns an empty result set when nothing matches" do
      assert {:ok, payload} = execute_tool(RecallMemory, nil, %{"query" => "nothing stored about this"})

      assert payload.memories == []
      assert payload.memory_count == 0
    end

    test "rejects a blank query" do
      assert {:error, message} = execute_tool(RecallMemory, nil, %{"query" => "   "})
      assert message =~ "query is required"
    end
  end
end
