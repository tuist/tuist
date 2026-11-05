defmodule Tuist.Push.FCM do
  @moduledoc """
  Sends notifications to the Tuist Android app through Firebase Cloud Messaging
  (HTTP v1 API), authenticated as the Firebase project's service account
  (`Tuist.Environment.fcm_service_account/0`).

  Messages are data-only so the app always handles them in
  `onMessageReceived`, which drops them when the user has turned notifications
  off on the device. A notification message would be shown by the system while
  the app is in the background, skipping that check.
  """

  alias Tuist.Environment

  @token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/firebase.messaging"
  # Access tokens last an hour; refresh a few minutes early.
  @token_margin_seconds 5 * 60
  # Undelivered notifications are dropped after a day, like on APNs.
  @ttl "86400s"

  def configured?, do: Environment.fcm_configured?()

  @doc """
  Sends `data` (a map of strings the app reads) to `device_token`. Returns the
  same results as `Tuist.Push.APNs.deliver/3`:

    * `:ok`
    * `{:error, :invalid_token}` when FCM says the token no longer reaches the
      app (`UNREGISTERED`, `SENDER_ID_MISMATCH`)
    * `{:error, {:retry, reason}}` for throttling, server, auth and transport errors
    * `{:error, {:rejected, reason}}` for anything else
  """
  def deliver(device_token, data) when is_map(data) do
    account = service_account()

    with {:ok, access_token} <- access_token(account) do
      message = %{
        "message" => %{
          "token" => device_token,
          "data" => Map.new(data, fn {key, value} -> {to_string(key), to_string(value)} end),
          "android" => %{"priority" => "HIGH", "ttl" => @ttl}
        }
      }

      "https://fcm.googleapis.com/v1/projects/#{account["project_id"]}/messages:send"
      |> Req.post(
        headers: [{"authorization", "Bearer " <> access_token}],
        json: message,
        finch: Tuist.Finch,
        retry: false
      )
      |> case do
        {:ok, %Req.Response{status: 200}} -> :ok
        {:ok, %Req.Response{status: status, body: body}} -> classify(status, reason(body), account)
        {:error, exception} -> {:error, {:retry, Exception.message(exception)}}
      end
    end
  end

  defp classify(_status, reason, _account) when reason in ["UNREGISTERED", "SENDER_ID_MISMATCH"],
    do: {:error, :invalid_token}

  defp classify(401, reason, account) do
    :persistent_term.erase(token_key(account))
    {:error, {:retry, reason}}
  end

  defp classify(status, reason, _account) when status == 429 or status >= 500, do: {:error, {:retry, reason}}
  defp classify(_status, reason, _account), do: {:error, {:rejected, reason}}

  # FCM puts its own error code in the details; the top-level status is generic.
  defp reason(%{"error" => %{"details" => details} = error}) when is_list(details) do
    Enum.find_value(details, error["status"], & &1["errorCode"])
  end

  defp reason(%{"error" => %{"status" => status}}), do: status
  defp reason(body) when is_binary(body), do: body
  defp reason(_body), do: "unknown"

  defp service_account, do: JSON.decode!(Environment.fcm_service_account())

  defp access_token(account) do
    now = System.system_time(:second)

    case :persistent_term.get(token_key(account), nil) do
      {token, expires_at} when now < expires_at - @token_margin_seconds ->
        {:ok, token}

      _ ->
        fetch_access_token(account, now)
    end
  end

  defp fetch_access_token(account, now) do
    {_, assertion} =
      account["private_key"]
      |> JOSE.JWK.from_pem()
      |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, %{
        "iss" => account["client_email"],
        "scope" => @scope,
        "aud" => @token_url,
        "iat" => now,
        "exp" => now + 3600
      })
      |> JOSE.JWS.compact()

    case Req.post(@token_url,
           form: [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion],
           finch: Tuist.Finch,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}} ->
        :persistent_term.put(token_key(account), {token, now + expires_in})
        {:ok, token}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:retry, "token exchange failed with #{status}"}}

      {:error, exception} ->
        {:error, {:retry, Exception.message(exception)}}
    end
  end

  defp token_key(account), do: {__MODULE__, account["client_email"]}
end
