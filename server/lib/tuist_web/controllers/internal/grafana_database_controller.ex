defmodule TuistWeb.Internal.GrafanaDatabaseController do
  @moduledoc """
  Grafana read-only access to the Tuist application database, backing the
  Business Intelligence dashboard's Infinity datasource.

  Uses the same read-only engine as the internal Atlas SQL runner
  (`Tuist.Ops.Database`): a SELECT/WITH/EXPLAIN/SHOW grammar gate, a
  `BEGIN READ ONLY` transaction, a clamped `statement_timeout`, and the
  least-privilege `tuist_ops_ro` role. The only difference is the auth boundary:
  `TuistWeb.Plugs.InternalGrafanaAuthPlug` gates this with a dedicated static
  token (Grafana Cloud can't present the Atlas workload-identity token), so the
  Grafana credential is independently revocable from the Atlas one.
  """

  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Ops.Database

  @doc """
  Run a read-only SQL statement. Body: `{"query": "...", "limit": n}`. Returns
  `{columns, rows, num_rows, truncated}` as JSON (see `Database.to_json_map/1`).
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
end
