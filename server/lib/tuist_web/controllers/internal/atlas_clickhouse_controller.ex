defmodule TuistWeb.Internal.AtlasClickHouseController do
  @moduledoc """
  Internal Atlas access to bounded, read-only ClickHouse queries.

  Authentication and rate limiting are provided by the Atlas internal
  pipeline. `Tuist.Ops.ClickHouse` owns query validation and resource limits.
  """

  use TuistWeb, :controller

  alias Tuist.Ops.ClickHouse

  def query(conn, %{"query" => statement} = request) when is_binary(statement) do
    opts =
      [params: Map.get(request, "params", %{})] ++
        case request do
          %{"limit" => limit} when is_integer(limit) and limit > 0 -> [limit: limit]
          _ -> []
        end

    case ClickHouse.execute(statement, opts) do
      {:ok, result} ->
        json(conn, query_response(result))

      {:error, :unavailable} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "clickhouse_unavailable"})

      {:error, :query_failed} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "query_failed"})

      {:error, :result_too_large} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "result_too_large"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def query(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing query"})
  end

  def tables(conn, _params) do
    case ClickHouse.list_table_overviews() do
      {:ok, tables} ->
        json(conn, %{tables: tables})

      {:error, :unavailable} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "clickhouse_unavailable"})

      {:error, :query_failed} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "query_failed"})

      {:error, :result_too_large} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "result_too_large"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def describe(conn, %{"database" => database, "name" => name}) do
    with {:ok, true} <- ClickHouse.app_table_exists?(database, name),
         {:ok, columns} <- ClickHouse.list_table_columns(database, name) do
      json(conn, %{database: database, name: name, columns: columns})
    else
      {:ok, false} ->
        conn |> put_status(:not_found) |> json(%{error: "table_not_found"})

      {:error, :unavailable} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "clickhouse_unavailable"})

      {:error, :query_failed} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "query_failed"})

      {:error, :result_too_large} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "result_too_large"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  defp query_response(result) do
    %{
      columns: result.columns,
      rows: result.rows,
      num_rows: result.num_rows,
      truncated: result.truncated?
    }
  end
end
