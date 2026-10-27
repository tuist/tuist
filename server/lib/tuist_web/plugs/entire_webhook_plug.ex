defmodule TuistWeb.Plugs.EntireWebhookPlug do
  @moduledoc """
  Verifies Entire's bearer JWT against the exact body before parsing JSON.
  Only durable receipt and Oban insertion run on the HTTP request path.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Entire
  alias Tuist.Entire.Client

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{request_path: "/webhooks/entire", method: "POST"} = conn, _opts) do
    if Client.configured?() do
      receive_delivery(conn)
    else
      conn |> send_resp(503, "Entire plugin is not configured") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp receive_delivery(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, body, conn} <- read_body(conn, length: 262_144, read_length: 262_144, read_timeout: 5_000),
         {:ok, delivery, jwt_id} <- Client.verify_delivery(token, body) do
      case Entire.accept_delivery(delivery, jwt_id) do
        {:ok, _} -> conn |> send_resp(200, "ok") |> halt()
        {:error, _} -> conn |> send_resp(503, "Delivery could not be stored") |> halt()
      end
    else
      {:error, :unavailable} -> conn |> send_resp(503, "Signing keys are temporarily unavailable") |> halt()
      {:more, _body, conn} -> conn |> send_resp(413, "Delivery is too large") |> halt()
      _ -> conn |> send_resp(401, "Invalid Entire delivery") |> halt()
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      conn |> send_resp(503, "Delivery could not be stored") |> halt()
  end
end
