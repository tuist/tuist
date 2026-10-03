defmodule Atlas.MCP.Tools.TuistPostgresToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.DescribeTuistPostgresTable
  alias Atlas.MCP.Tools.ListTuistPostgresTables
  alias Atlas.MCP.Tools.QueryTuistPostgres

  # Access is governed by the "observability" tool group at the tools/list /
  # dispatch layer (see Atlas.MCP.Server) — the same gate as the Grafana /
  # ClickHouse tools — not by an executive check inside these tools.

  describe "when the Tuist server is unreachable" do
    test "returns a clear error (no token file in test env), regardless of user role" do
      conn = %{role: :employee} |> insert_user!() |> mcp_conn()
      message = "The Tuist server database is not reachable from this environment."

      assert {:error, ^message} = execute_tool(QueryTuistPostgres, conn, %{"query" => "SELECT 1"})
      assert {:error, ^message} = execute_tool(ListTuistPostgresTables, conn, %{})
      assert {:error, ^message} = execute_tool(DescribeTuistPostgresTable, conn, %{"table" => "accounts"})
    end
  end

  describe "query output schema" do
    # Mirrors `Tuist.Ops.Database.to_json_map/1`, which the Tuist server's internal
    # /db/query endpoint returns verbatim. `json_response/2` raises in test when the
    # payload drifts from the published schema, which clients reject outright.
    test "accepts the envelope the Tuist server returns" do
      payload = %{
        "columns" => ["ok"],
        "rows" => [%{"ok" => 1}],
        "num_rows" => 1,
        "truncated" => false
      }

      response = Tool.json_response(payload, QueryTuistPostgres)

      assert response["structuredContent"] == payload
    end
  end

  describe "argument validation" do
    test "query requires a string query" do
      assert {:error, "query is required and must be a string."} =
               execute_tool(QueryTuistPostgres, %{}, %{})
    end

    test "describe requires a table" do
      assert {:error, "table is required and must be a string."} =
               execute_tool(DescribeTuistPostgresTable, %{}, %{})
    end
  end
end
