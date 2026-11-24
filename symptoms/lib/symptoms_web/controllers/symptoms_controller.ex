defmodule SymptomsWeb.SymptomsController do
  @moduledoc """
  The symptom API (README "Symptom log"), behind `SymptomsWeb.BearerAuth`:

  - `GET /api/v1/symptoms/log?after=<seq>&limit=<n>`: `{"revisions": [...],
    "next": seq}`; `after` defaults to 0 and `limit` to 500 (at most 500).
  - `GET /api/v1/symptoms/board`: `{"symptoms": [...]}`, today's top five.
  - `GET /api/v1/symptoms/:id`: the latest revision, or 404.

  A malformed `after` or `limit` is 400 `invalid_cursor` or `invalid_limit`.
  """
  use Phoenix.Controller, formats: [:json]

  alias Symptoms.Log

  def log(conn, params) do
    with {:ok, after_seq} <- integer(params["after"], 0, :invalid_cursor),
         {:ok, limit} <- integer(params["limit"], 500, :invalid_limit),
         true <- limit > 0 || {:error, :invalid_limit} do
      conn |> no_store() |> json(Log.page(after_seq, limit))
    else
      {:error, code} -> conn |> put_status(400) |> json(%{error: code})
    end
  end

  def board(conn, _params), do: conn |> no_store() |> json(%{symptoms: Log.board(5)})

  def show(conn, %{"id" => id}) do
    case Log.latest(id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      document -> conn |> no_store() |> json(document)
    end
  end

  defp integer(nil, default, _code), do: {:ok, default}

  defp integer(value, _default, code) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 and n < 9_223_372_036_854_775_807 -> {:ok, n}
      _ -> {:error, code}
    end
  end

  defp integer(_value, _default, code), do: {:error, code}

  defp no_store(conn), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
end
