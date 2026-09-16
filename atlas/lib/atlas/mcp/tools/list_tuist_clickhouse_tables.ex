defmodule Atlas.MCP.Tools.ListTuistClickhouseTables do
  @moduledoc """
  Lists tables in the Tuist server ClickHouse database.
  """

  use Atlas.MCP.Tool,
    name: "list_tuist_clickhouse_tables",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    # The payload is the raw JSON envelope returned by the Tuist server's internal
    # /clickhouse/tables endpoint (see Atlas.TuistServer.clickhouse_list_tables/1).
    # Its exact key set is owned by the remote Tuist service and is not modeled on
    # the Atlas side, so keep this open rather than assert a shape we do not control.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => true
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "List tables (with engine, estimated-row, and size stats) in the Tuist server (production) " <>
      "ClickHouse analytics database."
  end

  def execute(_conn, _args) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.clickhouse_list_tables()
    end
  end
end
