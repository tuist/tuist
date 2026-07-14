defmodule TuistWeb.Internal.AtlasDatabaseController do
  @moduledoc """
  Internal Atlas read-only access to the Tuist application database.

  Backed by `Tuist.Ops.Database` — the same read-only query engine that powers
  the `/ops/db` LiveView: a SELECT/WITH/EXPLAIN/SHOW grammar gate, a
  `BEGIN READ ONLY` transaction, and a clamped `statement_timeout`. The caller
  is authenticated by `TuistWeb.Plugs.InternalAtlasAuthPlug` (Atlas workload
  identity), so these endpoints are reachable only by the Atlas service account.
  """

  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Ops.Database

  @doc """
  Run a read-only SQL statement. Body: `{"query": "...", "limit": n}`.

  Runs through the least-privilege `tuist_ops_ro` role (when configured) so a
  write is blocked by role privileges, not only by the read-only transaction.
  """
  def query(conn, %{"query" => sql} = params) when is_binary(sql) do
    opts =
      [role: Environment.atlas_db_readonly_role()] ++
        case params do
          %{"limit" => limit} when is_integer(limit) and limit > 0 -> [limit: limit]
          _ -> []
        end

    case Database.execute(sql, opts) do
      {:ok, result} ->
        json(conn, Database.to_json_map(result))

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def query(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing query"})
  end

  @doc "List app-owned tables with size + estimated-row stats."
  def tables(conn, _params) do
    json(conn, %{tables: Database.list_table_overviews()})
  end

  @doc "Describe a single table's columns. 404 when the table is not visible."
  def describe(conn, %{"schema" => schema, "name" => name}) do
    if Database.app_table_exists?(schema, name) do
      json(conn, %{schema: schema, name: name, columns: Database.list_table_columns(schema, name)})
    else
      conn |> put_status(:not_found) |> json(%{error: "table_not_found"})
    end
  end
end
