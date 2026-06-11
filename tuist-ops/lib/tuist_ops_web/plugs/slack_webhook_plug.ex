defmodule TuistOpsWeb.Plugs.SlackWebhookPlug do
  @moduledoc """
  Verifies an inbound Slack webhook against the Slack signing scheme
  (`v0:<unix_timestamp>:<raw_body>` HMAC-SHA256, hex, sent as
  `X-Slack-Signature: v0=<hex>` plus `X-Slack-Request-Timestamp`).
  Bounds replay via a 5-minute tolerance on the timestamp.

  Wired into the slack-webhook pipeline in `TuistOpsWeb.Router`.
  Pulls the signing secret from `TuistOps.Environment` at call time
  so test code can override via Mimic.
  """

  @behaviour Plug

  import Plug.Conn

  alias TuistOps.Environment

  require Logger

  @signature_header "x-slack-signature"
  @timestamp_header "x-slack-request-timestamp"
  @timestamp_tolerance_seconds 300
  @signature_version "v0"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with [signature] <- get_req_header(conn, @signature_header),
         [timestamp_str] <- get_req_header(conn, @timestamp_header),
         {timestamp, ""} <- Integer.parse(timestamp_str),
         :ok <- check_timestamp(timestamp),
         {:ok, secret} <- resolve_secret(),
         true <- valid_signature?(conn, secret, signature, timestamp) do
      conn
    else
      _ ->
        conn |> send_resp(403, "Invalid Slack signature") |> halt()
    end
  end

  defp check_timestamp(ts) do
    now = System.system_time(:second)

    if abs(now - ts) <= @timestamp_tolerance_seconds do
      :ok
    else
      {:error, :timestamp_outside_tolerance}
    end
  end

  defp valid_signature?(conn, secret, signature, timestamp) do
    raw_body =
      conn.assigns
      |> Map.get(:raw_body, "")
      |> List.wrap()
      |> IO.iodata_to_binary()

    payload = "#{@signature_version}:#{timestamp}:#{raw_body}"
    expected_hex = :hmac |> :crypto.mac(:sha256, secret, payload) |> Base.encode16(case: :lower)
    expected = "#{@signature_version}=#{expected_hex}"

    Plug.Crypto.secure_compare(signature, expected)
  end

  defp resolve_secret do
    case Environment.slack_signing_secret() do
      nil -> :error
      "" -> :error
      secret when is_binary(secret) -> {:ok, secret}
    end
  end
end
