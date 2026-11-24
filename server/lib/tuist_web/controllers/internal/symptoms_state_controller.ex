defmodule TuistWeb.Internal.SymptomsStateController do
  @moduledoc """
  `GET /api/internal/symptoms/state?after=<cursor>`: the human state the
  symptoms evaluator reads back (`Tuist.Pulse.Symptoms.state_changes/1`).

  The evaluator presents a projected ServiceAccount token with the
  `tuist-symptoms-state` audience as a `Bearer` token; Kubernetes TokenReview
  validates it and only the configured evaluator ServiceAccount passes.
  `after` is a non-negative integer, 0 when absent.

  Errors are `{"error": "<code>"}`: 400 `invalid_cursor`, 401
  `unauthenticated`, 503 `unavailable` (not configured, or TokenReview failed).
  """
  use TuistWeb, :controller

  alias Tuist.Pulse.Symptoms

  def show(conn, params) do
    with {:ok, token} <- bearer_token(conn),
         :ok <- Symptoms.authenticate_evaluator(token),
         {:ok, after_seq} <- cursor(params["after"]) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(Symptoms.state_changes(after_seq))
    else
      {:error, :invalid_cursor} -> error(conn, :bad_request, "invalid_cursor")
      {:error, reason} when reason in [:not_configured, :unavailable] -> error(conn, :service_unavailable, "unavailable")
      {:error, _reason} -> error(conn, :unauthorized, "unauthenticated")
    end
  end

  defp cursor(nil), do: {:ok, 0}

  defp cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {seq, ""} when seq >= 0 and seq < 9_223_372_036_854_775_807 -> {:ok, seq}
      _ -> {:error, :invalid_cursor}
    end
  end

  defp cursor(_value), do: {:error, :invalid_cursor}

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: code})
  end
end
