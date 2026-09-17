defmodule Atlas.MCP.Tools.QueryTuistClickhouse do
  @moduledoc """
  Runs a bounded read-only SQL query against the Tuist server ClickHouse database.
  """

  use Atlas.MCP.Tool,
    name: "query_tuist_clickhouse",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" =>
            "A single read-only SQL statement (SELECT or WITH) to run against the Tuist server (production) ClickHouse analytics database."
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Maximum rows to return. Capped server-side."
        },
        "params" => %{
          "type" => "object",
          "additionalProperties" => true,
          "description" =>
            "Named ClickHouse query parameters bound to placeholders such as {project_ids:Array(Int64)}. Keys are placeholder names; values are the bound values."
        }
      }
    },
    # The Tuist read-only ClickHouse engine returns a uniform envelope for every
    # allowed statement: column names, rows (objects keyed by column), a row count,
    # and a truncation flag (see Atlas.TuistServer.clickhouse_query/2). The columns
    # depend on the query and rows carry arbitrary cell values, so keep the row item
    # schema open rather than enumerate dynamic columns.
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
    "Run a bounded read-only SQL query against the Tuist server (production) ClickHouse analytics " <>
      "database. Only SELECT/WITH statements are allowed; queries run with strict scan, memory, and " <>
      "row limits. Use named parameters (e.g. {project_ids:Array(Int64)}) via `params` rather than " <>
      "interpolating values. This database contains customer analytics, so query only what you need."
  end

  def execute(_conn, %{"query" => query} = args) when is_binary(query) do
    with :ok <- TuistPostgres.ensure_available() do
      TuistServer.clickhouse_query(query, opts(args))
    end
  end

  def execute(_conn, _args), do: {:error, "query is required and must be a string."}

  defp opts(args) do
    []
    |> maybe_opt(:limit, limit(args))
    |> maybe_opt(:params, params(args))
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp limit(%{"limit" => limit}) when is_integer(limit) and limit > 0, do: limit
  defp limit(_args), do: nil

  defp params(%{"params" => params}) when is_map(params) and map_size(params) > 0, do: params
  defp params(_args), do: nil
end
