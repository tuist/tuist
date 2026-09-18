defmodule Atlas.MCP.Tools.QueryTuistPostgres do
  @moduledoc """
  Runs a read-only SQL query against the Tuist server database.
  """

  use Atlas.MCP.Tool,
    name: "query_tuist_postgres",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" =>
            "A single read-only SQL statement (SELECT, WITH, EXPLAIN, or SHOW) to run against the Tuist server (production) Postgres database."
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Maximum rows to return. Capped server-side."
        }
      }
    },
    # The Tuist read-only ops/db engine returns a uniform envelope for every allowed
    # statement (SELECT/WITH/EXPLAIN/SHOW): column names, rows, a row count, and a
    # truncation flag (see Atlas.TuistServer.query/2). The columns depend on the query
    # and rows carry arbitrary cell values keyed by column name, so keep the row item
    # schema open (an empty schema accepts any object, list, or scalar) rather than
    # enumerate dynamic columns.
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["columns", "rows", "num_rows", "truncated"],
      "properties" => %{
        "columns" => %{"type" => "array", "items" => %{"type" => "string"}},
        "rows" => %{"type" => "array", "items" => %{}},
        "num_rows" => %{"type" => "integer"},
        "truncated" => %{"type" => "boolean"}
      }
    }

  alias Atlas.MCP.Tools.TuistPostgres
  alias Atlas.TuistServer

  @impl EMCP.Tool
  def description do
    "Run a read-only SQL query against the Tuist server (production) Postgres database. " <>
      "Only SELECT/WITH/EXPLAIN/SHOW statements are allowed; queries run in a read-only transaction " <>
      "with a statement timeout and a row cap. This database contains customer data, so query only " <>
      "what you need."
  end

  def execute(_conn, %{"query" => query} = args) when is_binary(query) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.query(query, limit: limit(args))
    end
  end

  def execute(_conn, _args), do: {:error, "query is required and must be a string."}

  defp limit(%{"limit" => limit}) when is_integer(limit) and limit > 0, do: limit
  defp limit(_args), do: nil
end
