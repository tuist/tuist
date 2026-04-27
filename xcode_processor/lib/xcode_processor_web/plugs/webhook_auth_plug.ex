defmodule XcodeProcessorWeb.Plugs.WebhookAuthPlug do
  @moduledoc false

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    secret = XcodeProcessor.Environment.webhook_secret()

    if is_nil(secret) or secret == "" do
      conn
      |> json_error(500, "Webhook secret not configured")
      |> halt()
    else
      verify_signature(conn, secret)
    end
  end

  defp verify_signature(conn, secret) do
    signature = conn |> get_req_header("x-webhook-signature") |> List.first()

    if is_nil(signature) do
      conn
      |> json_error(401, "Missing x-webhook-signature header")
      |> halt()
    else
      raw_body =
        conn.assigns[:raw_body]
        |> List.wrap()
        |> IO.iodata_to_binary()

      expected =
        :crypto.mac(:hmac, :sha256, secret, raw_body)
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(signature, expected) do
        conn
      else
        # Body lengths and a hash of the secret help diagnose drift between
        # the server and xcode_processor secret stores without leaking either.
        Logger.warning(fn ->
          "Webhook signature mismatch: body_size=#{byte_size(raw_body)} " <>
            "secret_fingerprint=#{secret_fingerprint(secret)}"
        end)

        conn
        |> json_error(403, "Invalid signature")
        |> halt()
      end
    end
  end

  defp secret_fingerprint(secret) do
    :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  defp json_error(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(%{error: message}))
  end
end
