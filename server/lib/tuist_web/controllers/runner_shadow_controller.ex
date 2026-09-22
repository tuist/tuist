defmodule TuistWeb.RunnerShadowController do
  @moduledoc """
  Read-only fleet demand for shadow scheduling. Restricted to the configured
  controller principal because the snapshot includes cross-account identifiers.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Shadow.Snapshot
  alias TuistWeb.RunnerControllerAuth

  def snapshot(conn, _params) do
    case RunnerControllerAuth.authenticate(conn) do
      :ok ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> json(Snapshot.capture())

      {:error, reason} when reason in [:missing_bearer, :unauthenticated, :not_service_account] ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid controller token"})

      {:error, {:wrong_principal, _}} ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"})

      {:error, _} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "controller authentication unavailable"})
    end
  end
end
