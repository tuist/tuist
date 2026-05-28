defmodule TuistWeb.Internal.KuraUsageController do
  use TuistWeb, :controller

  alias Boruta.BasicAuth
  alias Boruta.Oauth.Authorization.Client
  alias Tuist.Environment
  alias Tuist.Kura.Usage

  def create(conn, %{"schema_version" => 1, "events" => events}) when is_list(events) do
    case authorize(conn) do
      :ok ->
        case Usage.create_events(events) do
          {:ok, count} ->
            conn
            |> put_status(:accepted)
            |> json(%{accepted: count})

          {:error, :too_many_events} ->
            conn
            |> put_status(:payload_too_large)
            |> json(%{error: "too_many_events"})
        end

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload"})
  end

  # Mirrors the IntrospectController flow: parse Basic auth, gate on the
  # static Kura control-plane client, then delegate the secret + grant-type
  # check to Boruta so there's a single auth path for everything the Kura
  # control-plane client calls.
  defp authorize(conn) do
    with {:ok, client_id, client_secret} <- basic_credentials(conn),
         true <- dedicated_kura_client?(client_id),
         {:ok, _client} <-
           Client.authorize(
             id: client_id,
             source: %{type: "basic", value: client_secret},
             grant_type: "kura_usage"
           ) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp basic_credentials(conn) do
    with [header | _] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, [client_id, client_secret]} <- BasicAuth.decode(header) do
      {:ok, client_id, client_secret}
    else
      _ -> {:error, :missing_credentials}
    end
  end

  defp dedicated_kura_client?(client_id) do
    Environment.kura_control_plane_configured?() and
      client_id == Environment.kura_control_plane_client_id()
  end
end
