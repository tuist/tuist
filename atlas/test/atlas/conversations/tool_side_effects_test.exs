defmodule Atlas.Conversations.ToolSideEffectsTest do
  @moduledoc """
  Executes every tool the conversation policy allows and asserts it changes no
  rows besides its own `mcp.tool_called` audit event. PostgreSQL's per-transaction
  statistics see every insert, update and delete made inside the test's sandbox
  transaction, including writes hidden behind context functions.
  """
  use Atlas.DataCase, async: true

  import Atlas.ConversationsFixtures

  alias Atlas.Conversations.ToolPolicy
  alias Atlas.MCP.Server

  @moduletag :capture_log

  test "allowed tools are free of database side effects" do
    user = user_fixture(Atlas.Authorization.executive_scopes())

    conn = %{
      assigns: %{
        current_user: user,
        audit_interface: "worker",
        mcp_claims: %{"scopes" => ["mcp"], "conversation_run_id" => Ecto.UUID.generate()}
      }
    }

    writers =
      for name <- ToolPolicy.policy() |> Map.keys() |> Enum.sort(),
          before = writes(),
          _outcome = call(conn, name),
          changed = changed_tables(before, writes()),
          changed != [] do
        {name, changed}
      end

    assert writers == []

    # The detector itself catches the write-on-read tool the policy excludes.
    before = writes()
    call(conn, "list_gtm_research_topics")
    assert changed_tables(before, writes()) != []
    refute Map.has_key?(ToolPolicy.policy(), "list_gtm_research_topics")
  end

  # Some tools raise on missing arguments; run each call in its own process, as
  # `Atlas.Conversations.Tools` does, so the sweep covers every tool.
  defp call(conn, name) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => %{}}
    }

    task = Task.async(fn -> Server.handle_message(conn, request) end)
    Process.unlink(task.pid)
    Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill)
  end

  defp writes do
    Atlas.Repo.query!("SELECT relname, n_tup_ins + n_tup_upd + n_tup_del FROM pg_stat_xact_user_tables").rows
    |> Map.new(fn [table, count] -> {table, count} end)
  end

  defp changed_tables(before, current) do
    current
    |> Enum.reject(fn {table, count} -> table == "audit_activities" or Map.get(before, table, 0) == count end)
    |> Enum.map(&elem(&1, 0))
  end
end
