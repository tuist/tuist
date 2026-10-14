defmodule TuistWeb.Plugs.OriginWebhookPlug do
  @moduledoc "Verifies Origin's Ed25519 digest signature before parsing the raw body."
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.Origin.Auth
  alias Tuist.Origin.WebhookWorker

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{request_path: "/webhooks/origin", method: "POST"} = conn, _) do
    with {:ok, body, conn} <- read_body(conn, length: 262_144, read_timeout: 5_000),
         {:ok, id} <- Auth.verify_webhook(body, Map.new(conn.req_headers)),
         {:ok, %{"deliveryId" => ^id, "appId" => app_id, "event" => %{"type" => type}} = envelope} <- JSON.decode(body),
         %{app_id: ^app_id} <- Environment.origin_app_credentials(),
         true <- is_binary(type),
         args = Map.take(envelope, ["deliveryId", "appId", "installationId"]),
         args = Map.put(args, "event", Map.take(envelope["event"], ["id", "type"])),
         {:ok, _} <- args |> WebhookWorker.new() |> Oban.insert() do
      conn |> send_resp(202, "") |> halt()
    else
      {:more, _, conn} -> conn |> send_resp(413, "") |> halt()
      {:error, :verification_unavailable} -> conn |> send_resp(503, "") |> halt()
      {:error, %Ecto.Changeset{}} -> conn |> send_resp(503, "") |> halt()
      _ -> conn |> send_resp(403, "") |> halt()
    end
  end

  def call(%{request_path: "/webhooks/origin"} = conn, _), do: conn |> send_resp(405, "") |> halt()
  def call(conn, _), do: conn
end
