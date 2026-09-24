defmodule Atlas.MCP.Tools.DescribeTuistPostgresTable do
  @moduledoc """
  Describes the columns of a table in the Tuist server database.
  """

  use Atlas.MCP.Tool,
    name: "describe_tuist_postgres_table",
    schema: %{
      "type" => "object",
      "required" => ["table"],
      "properties" => %{
        "table" => %{"type" => "string", "description" => "The table name to describe."},
        "schema" => %{
          "type" => "string",
          "description" => "The schema the table belongs to. Defaults to \"public\"."
        }
      }
    },
    # The payload is the raw JSON envelope returned by the Tuist server's internal
    # /db/tables/:schema/:table endpoint (see Atlas.TuistServer.describe_table/3).
    # Its exact key set is owned by the remote Tuist service and is not modeled on
    # the Atlas side, so keep this open rather than assert a shape we do not control.
    # json_response/2 already guarantees the top level is an object.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => true
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "Describe the columns (name, type, nullability, default) of a table in the Tuist server " <>
      "(production) Postgres database."
  end

  def execute(_conn, %{"table" => table} = args) when is_binary(table) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.describe_table(String.trim(table), schema(args))
    end
  end

  def execute(_conn, _args), do: {:error, "table is required and must be a string."}

  defp schema(%{"schema" => schema}) when is_binary(schema) do
    case String.trim(schema) do
      "" -> "public"
      trimmed -> trimmed
    end
  end

  defp schema(_args), do: "public"
end
