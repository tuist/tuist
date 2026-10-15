defmodule TuistWeb.Plugs.OriginWebhookPlug do
  @moduledoc "Bounded raw-body Origin webhook verification and durable lifecycle dispatch."
  @behaviour Plug
  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Origin.Signatures
  alias Tuist.Origin.WebhookWorker

  @impl true
  def init(options), do: options

  @impl true
  def call(%{method: "POST", request_path: "/webhooks/origin"} = conn, _options) do
    case read_body(conn, length: 512_000, read_length: 512_000, read_timeout: 5_000) do
      {:ok, body, conn} -> verify_and_dispatch(conn, body)
      {:more, _body, conn} -> conn |> send_resp(413, "Payload Too Large") |> halt()
      {:error, _} -> conn |> send_resp(400, "Invalid body") |> halt()
    end
  end

  def call(conn, _options), do: conn

  defp verify_and_dispatch(conn, body) do
    headers = Map.new(conn.req_headers)

    with :ok <- Signatures.verify_webhook(body, headers),
         {:ok,
          %{
            "appId" => app_id,
            "deliveryId" => delivery_id,
            "event" => %{"type" => type}
          } = envelope} <- Jason.decode(body),
         true <- app_id == Environment.origin_app_id() and delivery_id == headers["webhook-id"],
         true <- is_binary(delivery_id) and is_binary(type) do
      dispatch(conn, delivery_id, envelope["installationId"], type)
    else
      {:error, :origin_keys_unavailable} -> conn |> send_resp(503, "Try again") |> halt()
      _ -> conn |> send_resp(401, "Invalid Origin delivery") |> halt()
    end
  end

  defp dispatch(conn, delivery_id, installation_id, "installation." <> _event)
       when is_binary(installation_id) and installation_id != "" do
    case %{delivery_id: delivery_id, installation_id: installation_id}
         |> WebhookWorker.new()
         |> Oban.insert() do
      {:ok, _} -> conn |> send_resp(202, "Accepted") |> halt()
      {:error, _} -> conn |> send_resp(503, "Try again") |> halt()
    end
  end

  defp dispatch(conn, _delivery_id, _installation_id, "installation." <> _event),
    do: conn |> send_resp(401, "Missing installation") |> halt()

  defp dispatch(conn, _delivery_id, _installation_id, _type),
    do: conn |> send_resp(204, "") |> halt()
end
