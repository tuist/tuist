defmodule TuistWeb.Internal.KuraUsageController do
  use TuistWeb, :controller

  alias Tuist.Kura.ControlPlaneAuth
  alias Tuist.Kura.Usage

  def create(conn, %{"schema_version" => 1, "events" => events}) when is_list(events) do
    with :ok <- ControlPlaneAuth.authorize(conn, "kura_usage"),
         {:ok, count} <- Usage.create_events(events) do
      conn
      |> put_status(:accepted)
      |> json(%{accepted: count})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})

      {:error, :too_many_events} ->
        conn
        |> put_status(:payload_too_large)
        |> json(%{error: "too_many_events"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end
end
