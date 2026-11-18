defmodule Tuist.Accounts.AISubscriptions.ChatGPT do
  @moduledoc """
  ChatGPT device authorization, following OpenAI's published Codex device flow.
  It requires an operator-configured OAuth client (`TUIST_CHATGPT_CLIENT_ID`)
  with device authorization enabled; there is no built-in client ID fallback.
  Requests are bounded, never retried or redirected, and failures are reported
  as status-only reasons so provider bodies never reach logs or the UI.
  """

  alias Tuist.Environment

  @issuer "https://auth.openai.com"
  @verification_url @issuer <> "/codex/device"

  def client_id do
    case Environment.chatgpt_client_id() do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :chatgpt_not_configured}
    end
  end

  def start do
    with {:ok, client_id} <- client_id(),
         {:ok, body} <- request("/api/accounts/deviceauth/usercode", json: %{client_id: client_id}),
         %{"device_auth_id" => device_id} when is_binary(device_id) <- body,
         user_code when is_binary(user_code) <- body["user_code"] || body["usercode"],
         true <- byte_size(device_id) in 1..4096 and byte_size(user_code) in 1..128,
         {:ok, interval} <- interval(body["interval"]) do
      {:ok,
       %{
         "device_auth_id" => device_id,
         "user_code" => user_code,
         "client_id" => client_id,
         "interval" => interval,
         "verification_url" => @verification_url
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  end

  def poll(login) do
    with {:ok, body} <-
           request("/api/accounts/deviceauth/token", json: Map.take(login, ["device_auth_id", "user_code"])),
         %{"authorization_code" => code, "code_verifier" => verifier} when is_binary(code) and is_binary(verifier) <-
           body do
      exchange(
        grant_type: "authorization_code",
        client_id: login["client_id"],
        code: code,
        code_verifier: verifier,
        redirect_uri: @issuer <> "/deviceauth/callback"
      )
    else
      # The device endpoint answers 403/404 until the user approves the code.
      {:error, {:http_status, status}} when status in [403, 404] -> {:error, :authorization_pending}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  end

  @doc """
  Refreshes with the client the tokens were issued to, so rotating
  `TUIST_CHATGPT_CLIENT_ID` does not invalidate existing subscriptions.
  """
  def refresh(refresh_token, client_id) when is_binary(client_id) and client_id != "" do
    exchange(grant_type: "refresh_token", client_id: client_id, refresh_token: refresh_token)
  end

  def refresh(refresh_token, _client_id) do
    with {:ok, client_id} <- client_id() do
      exchange(grant_type: "refresh_token", client_id: client_id, refresh_token: refresh_token)
    end
  end

  defp exchange(form) do
    with {:ok, body} <- request("/oauth/token", form: form),
         %{"access_token" => access} when is_binary(access) <- body,
         refresh when is_binary(refresh) <- body["refresh_token"] || form[:refresh_token],
         true <- byte_size(access) in 1..65_536 and byte_size(refresh) in 1..65_536,
         {:ok, expires_at} <- expiry(body["expires_in"], access) do
      {:ok, %{access_token: access, refresh_token: refresh, expires_at: expires_at}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp expiry(seconds, _token) when is_integer(seconds) and seconds in 1..31_536_000 do
    {:ok, DateTime.add(DateTime.utc_now(:second), seconds, :second)}
  end

  # Some exchanges omit `expires_in`. The token came over the HTTPS token
  # response, so its `exp` claim is only used to schedule a refresh.
  defp expiry(nil, token) do
    with [_header, payload, _signature] <- String.split(token, ".", parts: 3),
         {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => seconds}} when is_integer(seconds) <- JSON.decode(decoded),
         {:ok, expires_at} <- DateTime.from_unix(seconds),
         true <- DateTime.after?(expires_at, DateTime.utc_now(:second)) do
      {:ok, expires_at}
    else
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp expiry(_seconds, _token), do: {:error, :invalid_provider_response}

  defp request(path, body_options) do
    options =
      [
        url: @issuer <> path,
        retry: false,
        redirect: false,
        receive_timeout: 15_000,
        connect_options: [timeout: 5_000]
      ] ++ body_options

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, _reason} -> {:error, :provider_unavailable}
    end
  end

  defp interval(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> interval(number)
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp interval(value) when is_integer(value) and value in 1..60, do: {:ok, max(value, 5)}
  defp interval(_value), do: {:error, :invalid_provider_response}
end
