defmodule Atlas.MCP.Tools.ListTuistPostgresTables do
  @moduledoc """
  Lists tables in the Tuist server database.
  """

  use Atlas.MCP.Tool,
    name: "list_tuist_postgres_tables",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    # The payload is the raw JSON envelope returned by the Tuist server's internal
    # /db/tables endpoint (see Atlas.TuistServer.list_tables/1). Its exact key set
    # is owned by the remote Tuist service and is not modeled on the Atlas side, so
    # keep this open rather than assert a shape we do not control. json_response/2
    # already guarantees the top level is an object.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => true
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "List app-owned tables (with size and estimated-row stats) in the Tuist server (production) " <>
      "Postgres database."
  end

  def execute(_conn, _args) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.list_tables()
    end
  end
end
