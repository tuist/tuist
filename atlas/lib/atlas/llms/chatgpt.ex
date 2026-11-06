defmodule Atlas.LLMs.ChatGPT do
  @moduledoc """
  ChatGPT device authorization. Requires an operator-configured OpenAI OAuth
  client with device authorization enabled; there is no built-in client ID fallback.
  """

  alias Atlas.LLMs.ChatGPT.Config

  @issuer "https://auth.openai.com"
  @verification_url @issuer <> "/codex/device"

  def client_id, do: Config.client_id()

  def start do
    with {:ok, client_id} <- Config.client_id(),
         {:ok, body} <- request("/api/accounts/deviceauth/usercode", json: %{client_id: client_id}),
         %{"device_auth_id" => device_id} <- body,
         user_code when is_binary(user_code) <- body["user_code"] || body["usercode"],
         true <- is_binary(device_id) and byte_size(device_id) in 1..4096,
         true <- byte_size(user_code) in 1..128,
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
           request("/api/accounts/deviceauth/token",
             json: Map.take(login, ["device_auth_id", "user_code"])
           ),
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
      {:error, {:http_status, status}} when status in [403, 404] -> {:error, :authorization_pending}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  end

  def refresh(refresh_token) do
    with {:ok, client_id} <- Config.client_id() do
      exchange(grant_type: "refresh_token", client_id: client_id, refresh_token: refresh_token)
    end
  end

  defp exchange(form) do
    with {:ok, body} <- request("/oauth/token", form: form),
         %{"access_token" => access} when is_binary(access) <- body,
         refresh when is_binary(refresh) <- body["refresh_token"] || form[:refresh_token],
         true <- byte_size(access) in 1..65_536 and byte_size(refresh) in 1..65_536,
         {:ok, expires_at} <- expiry(body["expires_in"], access) do
      {:ok,
       %{
         access_token: access,
         refresh_token: refresh,
         expires_at: expires_at
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp expiry(seconds, _token) when is_integer(seconds) and seconds in 1..31_536_000 do
    {:ok, DateTime.add(DateTime.utc_now(:second), seconds, :second)}
  end

  # Some ChatGPT exchanges omit expires_in. The HTTPS token response is trusted;
  # decoding exp only schedules refresh and never authorizes an Atlas identity.
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
    options = [
      url: @issuer <> path,
      retry: false,
      redirect: false,
      receive_timeout: 15_000,
      finch: [conn_opts: [transport_opts: [timeout: 5_000]]]
    ]

    case Req.post(options ++ body_options) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
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
