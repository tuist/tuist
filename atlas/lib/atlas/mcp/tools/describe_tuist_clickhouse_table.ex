defmodule Atlas.MCP.Tools.DescribeTuistClickhouseTable do
  @moduledoc """
  Describes the columns of a table in the Tuist server ClickHouse database.
  """

  use Atlas.MCP.Tool,
    name: "describe_tuist_clickhouse_table",
    schema: %{
      "type" => "object",
      "required" => ["table", "database"],
      "properties" => %{
        "table" => %{"type" => "string", "description" => "The table name to describe."},
        "database" => %{
          "type" => "string",
          "description" =>
            "The ClickHouse database the table belongs to (the `database` value reported by list_tuist_clickhouse_tables)."
        }
      }
    },
    # The payload is the raw JSON envelope returned by the Tuist server's internal
    # /clickhouse/tables/:database/:name endpoint (see
    # Atlas.TuistServer.clickhouse_describe_table/3). Its exact key set is owned by
    # the remote Tuist service and is not modeled on the Atlas side, so keep this open.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => true
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "Describe the columns (name, type, default, primary/sorting-key membership) of a table in the " <>
      "Tuist server (production) ClickHouse analytics database."
  end

  def execute(_conn, %{"table" => table, "database" => database}) when is_binary(table) and is_binary(database) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.clickhouse_describe_table(String.trim(table), String.trim(database))
    end
  end

  def execute(_conn, _args), do: {:error, "table and database are required and must be strings."}
end
