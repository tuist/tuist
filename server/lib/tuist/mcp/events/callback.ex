defmodule Tuist.MCP.Events.Callback do
  @moduledoc false

  alias Tuist.OAuth2.SSRFGuard

  @timeout_ms 5_000
  @maximum_response_bytes 4_096

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

    with {:ok, response} <-
           post_with_supervisor(url, secret, subscription_id, message_id, body, Tuist.MCP.Events.VerificationSupervisor),
         true <- response.status in 200..299,
         {:ok, %{"challenge" => echoed}} when is_binary(echoed) <- decode_body(response.body),
         true <- byte_size(echoed) == byte_size(challenge) and Plug.Crypto.secure_compare(echoed, challenge) do
      :ok
    else
      {:error, :invalid_callback_url} -> {:error, :invalid_url}
      {:error, :timeout} -> {:error, :timeout}
      {:error, :overloaded} -> {:error, :unreachable}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unreachable}
      _ -> {:error, :challenge_failed}
    end
  end

  defp decode_body(%{} = body), do: {:ok, body}
  defp decode_body(body) when is_binary(body), do: JSON.decode(body)
  defp decode_body(_body), do: :error

  def post(url, secret, subscription_id, message_id, body) do
    post_with_supervisor(url, secret, subscription_id, message_id, body, Tuist.MCP.Events.DeliverySupervisor)
  end

  defp post_with_supervisor(url, secret, subscription_id, message_id, body, supervisor) do
    timestamp = System.system_time(:second)

    headers = [
      {"content-type", "application/json"},
      {"webhook-id", message_id},
      {"webhook-timestamp", Integer.to_string(timestamp)},
      {"webhook-signature", sign(message_id, timestamp, body, secret)},
      {"x-mcp-subscription-id", subscription_id}
    ]

    try do
      task = Task.Supervisor.async_nolink(supervisor, fn -> bounded_request(url, headers, body) end)

      case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
        nil -> {:error, :timeout}
      end
    rescue
      e in RuntimeError ->
        if String.starts_with?(e.message, "reached the maximum number of tasks for this task supervisor"),
          do: {:error, :overloaded},
          else: reraise(e, __STACKTRACE__)
    end
  end

  defp bounded_request(url, headers, body) do
    {:ok, timer} = :timer.kill_after(@timeout_ms + 100, self())

    try do
      send_request(url, headers, body)
    after
      :timer.cancel(timer)
    end
  end

  defp send_request(url, headers, body) do
    with %URI{scheme: "https"} <- URI.parse(url),
         {:ok, pinned_url, hostname} <- SSRFGuard.pin(url) do
      Req.post(pinned_url,
        headers: headers,
        body: body,
        receive_timeout: @timeout_ms,
        retry: false,
        redirect: false,
        connect_options: SSRFGuard.connect_options(hostname),
        into: &bounded_response/2
      )
    else
      _ -> {:error, :invalid_callback_url}
    end
  end

  defp bounded_response({:data, chunk}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(chunk) <= @maximum_response_bytes do
      {:cont, {request, %{response | body: body <> chunk}}}
    else
      {:halt, {request, %{response | body: :response_too_large}}}
    end
  end
end
