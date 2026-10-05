defmodule Tuist.MCP.Events.Callback do
  @moduledoc false

  alias Tuist.OAuth2.SSRFGuard

  @timeout_ms 5_000

  def valid_secret?("whsec_" <> encoded) do
    case Base.decode64(encoded) do
      {:ok, key} -> byte_size(key) in 24..64
      :error -> false
    end
  end

  def valid_secret?(_secret), do: false

  def sign(id, timestamp, body, "whsec_" <> encoded) do
    {:ok, key} = Base.decode64(encoded)

    signature =
      :hmac
      |> :crypto.mac(:sha256, key, "#{id}.#{timestamp}.#{body}")
      |> Base.encode64()

    "v1,#{signature}"
  end

  def verify(url, secret, subscription_id) do
    challenge = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    body = JSON.encode!(%{"type" => "verification", "challenge" => challenge})
    message_id = "msg_verification_" <> Ecto.UUID.generate()

    with {:ok, response} <- post(url, secret, subscription_id, message_id, body),
         true <- response.status in 200..299,
         {:ok, %{"challenge" => echoed}} when is_binary(echoed) <- decode_body(response.body),
         true <- byte_size(echoed) == byte_size(challenge) and Plug.Crypto.secure_compare(echoed, challenge) do
      :ok
    else
      {:error, :invalid_callback_url} -> {:error, :invalid_url}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unreachable}
      _ -> {:error, :challenge_failed}
    end
  end

  defp decode_body(%{} = body), do: {:ok, body}
  defp decode_body(body) when is_binary(body), do: JSON.decode(body)
  defp decode_body(_body), do: :error

  def post(url, secret, subscription_id, message_id, body) do
    timestamp = System.system_time(:second)

    headers = [
      {"content-type", "application/json"},
      {"webhook-id", message_id},
      {"webhook-timestamp", Integer.to_string(timestamp)},
      {"webhook-signature", sign(message_id, timestamp, body, secret)},
      {"x-mcp-subscription-id", subscription_id}
    ]

    with %URI{scheme: "https"} <- URI.parse(url),
         {:ok, pinned_url, hostname} <- SSRFGuard.pin(url) do
      Req.post(pinned_url,
        headers: headers,
        body: body,
        receive_timeout: @timeout_ms,
        retry: false,
        redirect: false,
        connect_options: SSRFGuard.connect_options(hostname)
      )
    else
      _ -> {:error, :invalid_callback_url}
    end
  end
end
