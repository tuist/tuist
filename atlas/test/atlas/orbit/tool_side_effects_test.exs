defmodule Atlas.Orbit.ToolSideEffectsTest do
  @moduledoc """
  Executes every tool the thread policy allows and asserts it changes no
  rows besides its own `mcp.tool_called` audit event. PostgreSQL's per-transaction
  statistics see every insert, update and delete made inside the test's sandbox
  transaction, including writes hidden behind context functions.
  """
  use Atlas.DataCase, async: true

  import Atlas.OrbitFixtures

  alias Atlas.MCP.Server
  alias Atlas.Orbit.ToolPolicy
  alias Atlas.Repo

  @moduletag :capture_log

  test "allowed tools are free of database side effects" do
    user = user_fixture(Atlas.Authorization.executive_scopes())

    conn = %{
      assigns: %{
        current_user: user,
        audit_interface: "worker",
        mcp_claims: %{"scopes" => ["mcp"], "orbit_run_id" => Ecto.UUID.generate()}
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
  end

  test "the detector catches the write-on-read tool the policy excludes" do
    user = user_fixture(Atlas.Authorization.executive_scopes())

    conn = %{
      assigns: %{
        current_user: user,
        audit_interface: "worker",
        mcp_claims: %{"scopes" => ["mcp"], "orbit_run_id" => Ecto.UUID.generate()}
      }
    }

    before = writes()
    call(conn, "list_gtm_research_topics")
    assert Enum.any?(changed_tables(before, writes()), fn {_schema, table} -> table == "gtm_signal_queries" end)
    refute Map.has_key?(ToolPolicy.policy(), "list_gtm_research_topics")
  end

  test "same-named tables in isolated schemas retain independent write counters" do
    user_fixture()
    schema = "orbit_tool_stats_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{schema}")

    for table <- ["users", "oban_jobs"] do
      before = writes()
      Repo.query!("CREATE TABLE #{schema}.#{table} (id bigint)")

      assert changed_tables(before, writes()) == []

      before = writes()
      Repo.query!("INSERT INTO #{schema}.#{table} VALUES (1)")
      assert changed_tables(before, writes()) == [{schema, table}]
    end
  end

  # Some tools raise on missing arguments; run each call in its own process, as
  # `Atlas.Orbit.Tools` does, so the sweep covers every tool.
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
    # This view includes isolated migration schemas, not just the application's
    # schema. Same-named tables must never overwrite each other's counters.
    Repo.query!("SELECT schemaname, relname, n_tup_ins + n_tup_upd + n_tup_del FROM pg_stat_xact_user_tables").rows
    |> Map.new(fn [schema, table, count] -> {{schema, table}, count} end)
  end

  defp changed_tables(before, current) do
    current
    |> Enum.reject(fn {{_schema, table} = relation, count} ->
      table == "audit_activities" or Map.get(before, relation, 0) == count
    end)
    |> Enum.map(&elem(&1, 0))
  end
end
