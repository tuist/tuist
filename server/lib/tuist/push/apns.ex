defmodule Tuist.Push.APNs do
  @moduledoc """
  Sends notifications to the Tuist iOS app through the Apple Push Notification
  service, authenticated with the team's token-auth key (`Tuist.Environment.apns_*`).

  A registration's `environment` picks the endpoint: Debug builds register
  `sandbox` tokens and Release builds `production` ones. The key must be enabled
  for the environment it's used against, or APNs answers
  `BadEnvironmentKeyInToken`.
  """

  alias Tuist.Environment

  @endpoints %{
    "production" => "https://api.push.apple.com",
    "sandbox" => "https://api.sandbox.push.apple.com"
  }

  # APNs rejects provider tokens older than an hour and throttles a key that
  # mints new ones more often than every 20 minutes.
  @token_lifetime_seconds 50 * 60

  # Undelivered notifications are dropped after a day: a preview that old is no
  # longer news.
  @expiration_seconds 24 * 60 * 60

  def endpoints, do: Map.values(@endpoints)

  def configured?, do: Environment.apns_configured?()

  @doc """
  Sends `payload` (the APNs JSON body) to `device_token`. Returns:

    * `:ok`
    * `{:error, :invalid_token}` when APNs says the token no longer reaches the
      app (`410 Unregistered`, `BadDeviceToken`, `DeviceTokenNotForTopic`), so
      the registration should be retired
    * `{:error, {:retry, reason}}` for throttling, server and transport errors
    * `{:error, {:rejected, reason}}` for anything else, which retrying won't fix
  """
  def deliver(environment, device_token, payload) when is_map_key(@endpoints, environment) do
    url = "#{Map.fetch!(@endpoints, environment)}/3/device/#{device_token}"

    headers = [
      {"authorization", "bearer " <> provider_token()},
      {"apns-topic", Environment.apns_topic()},
      {"apns-push-type", "alert"},
      {"apns-priority", "10"},
      {"apns-expiration", to_string(System.system_time(:second) + @expiration_seconds)}
    ]

    case Req.post(url, headers: headers, json: payload, finch: Tuist.Finch, retry: false) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        classify(status, reason(body))

      {:error, exception} ->
        {:error, {:retry, Exception.message(exception)}}
    end
  end

  defp classify(410, _reason), do: {:error, :invalid_token}
  defp classify(400, reason) when reason in ["BadDeviceToken", "DeviceTokenNotForTopic"], do: {:error, :invalid_token}

  defp classify(403, reason) when reason in ["ExpiredProviderToken", "InvalidProviderToken"] do
    :persistent_term.erase(token_key())
    {:error, {:retry, reason}}
  end

  defp classify(status, reason) when status == 429 or status >= 500, do: {:error, {:retry, reason}}
  defp classify(_status, reason), do: {:error, {:rejected, reason}}

  defp reason(%{"reason" => reason}), do: reason
  defp reason(body) when is_binary(body), do: body
  defp reason(_body), do: "unknown"

  defp provider_token do
    now = System.system_time(:second)

    case :persistent_term.get(token_key(), nil) do
      {token, issued_at} when now - issued_at < @token_lifetime_seconds ->
        token

      _ ->
        token = sign(now)
        :persistent_term.put(token_key(), {token, now})
        token
    end
  end

  defp token_key, do: {__MODULE__, Environment.apns_team_id(), Environment.apns_key_id()}

  defp sign(issued_at) do
    {_, token} =
      Environment.apns_private_key()
      |> JOSE.JWK.from_pem()
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => Environment.apns_key_id()}, %{
        "iss" => Environment.apns_team_id(),
        "iat" => issued_at
      })
      |> JOSE.JWS.compact()

    token
  end
end
