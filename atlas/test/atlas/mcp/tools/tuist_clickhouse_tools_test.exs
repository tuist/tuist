defmodule Atlas.MCP.Tools.TuistClickhouseToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.DescribeTuistClickhouseTable
  alias Atlas.MCP.Tools.ListTuistClickhouseTables
  alias Atlas.MCP.Tools.QueryTuistClickhouse

  # Access is governed by the "observability" tool group at the tools/list /
  # dispatch layer (see Atlas.MCP.Server), the same gate as the Postgres tools.

  describe "when the Tuist server is unreachable" do
    test "returns a clear error (no token file in test env), regardless of user role" do
      conn = %{role: :employee} |> insert_user!() |> mcp_conn()
      message = "The Tuist server database is not reachable from this environment."

      assert {:error, ^message} = execute_tool(QueryTuistClickhouse, conn, %{"query" => "SELECT 1"})
      assert {:error, ^message} = execute_tool(ListTuistClickhouseTables, conn, %{})

      assert {:error, ^message} =
               execute_tool(DescribeTuistClickhouseTable, conn, %{"table" => "command_events", "database" => "default"})
    end
  end

  describe "argument validation" do
    test "query requires a string query" do
      assert {:error, "query is required and must be a string."} =
               execute_tool(QueryTuistClickhouse, %{}, %{})
    end

    test "describe requires a table and a database" do
      assert {:error, "table and database are required and must be strings."} =
               execute_tool(DescribeTuistClickhouseTable, %{}, %{"table" => "command_events"})
    end
  end
end
