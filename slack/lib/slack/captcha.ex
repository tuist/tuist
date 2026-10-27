defmodule Slack.Captcha do
  @moduledoc """
  Cloudflare Turnstile verification.

  `verify/2` POSTs the token returned by the client-side widget to
  Cloudflare's `siteverify` endpoint and returns `:ok` when the challenge
  passes or `{:error, reason}` otherwise.

  If no secret key is configured (e.g. local development), verification
  is a no-op and always returns `:ok`.
  """

  require Logger

  @endpoint "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  def site_key do
    Application.get_env(:slack, :captcha, [])[:site_key]
  end

  def secret_key do
    Application.get_env(:slack, :captcha, [])[:secret_key]
  end

  def enabled?, do: is_binary(secret_key()) and secret_key() != ""

  def verify(token, remote_ip \\ nil) do
    cond do
      not enabled?() ->
        :ok

      not is_binary(token) or token == "" ->
        {:error, :missing_token}

      true ->
        do_verify(token, remote_ip)
    end
  end

  defp do_verify(token, remote_ip) do
    body = maybe_put(%{secret: secret_key(), response: token}, :remoteip, remote_ip)

    case Req.post(@endpoint, form: body, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{status: 200, body: %{"success" => false, "error-codes" => codes}}} ->
        Logger.warning("Turnstile verification failed: #{inspect(codes)}")
        {:error, {:captcha_failed, codes}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Turnstile returned unexpected response: #{status} #{inspect(body)}")
        {:error, {:unexpected_response, status}}

      {:error, exception} ->
        Logger.warning("Turnstile request failed: #{Exception.message(exception)}")
        {:error, {:request_failed, exception}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
