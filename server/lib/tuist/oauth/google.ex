defmodule Tuist.OAuth.Google do
  @moduledoc """
  Verifies Google One Tap identity tokens against Google's public signing keys.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore

  @public_keys_url "https://www.googleapis.com/oauth2/v3/certs"
  @cache_key [__MODULE__, "public_keys"]

  def verify_identity_token(token, nonce)
      when is_binary(token) and byte_size(token) <= 16_384 and is_binary(nonce) and nonce != "" do
    with %JOSE.JWS{fields: %{"kid" => key_id}} when is_binary(key_id) <- JOSE.JWT.peek_protected(token),
         {:ok, keys} <- public_keys(),
         %{} = key <- Enum.find(keys, &(&1["kid"] == key_id)),
         {true, %JOSE.JWT{fields: claims}, _} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], token),
         :ok <- validate_claims(claims, nonce) do
      {:ok, claims}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  def verify_identity_token(_token, _nonce), do: {:error, :invalid_token}

  def authoritative_email?(%{"email" => email, "email_verified" => true} = claims) when is_binary(email) do
    String.ends_with?(email, "@gmail.com") or
      (is_binary(claims["hd"]) and claims["hd"] != "")
  end

  def authoritative_email?(_claims), do: false

  defp validate_claims(claims, nonce) do
    with :ok <- validate_client(claims),
         :ok <- validate_timestamps(claims) do
      cond do
        claims["nonce"] != nonce ->
          {:error, :invalid_nonce}

        not is_binary(claims["sub"]) or claims["sub"] == "" ->
          {:error, :missing_subject}

        not is_binary(claims["email"]) or claims["email"] == "" or claims["email_verified"] != true ->
          {:error, :unverified_email}

        true ->
          :ok
      end
    end
  end

  defp validate_client(claims) do
    audience = Environment.google_oauth_client_id()

    cond do
      not is_binary(audience) or audience == "" or claims["aud"] != audience ->
        {:error, :invalid_audience}

      claims["iss"] not in ["accounts.google.com", "https://accounts.google.com"] ->
        {:error, :invalid_issuer}

      true ->
        :ok
    end
  end

  defp validate_timestamps(claims) do
    now = DateTime.to_unix(DateTime.utc_now())

    cond do
      not is_integer(claims["exp"]) or claims["exp"] <= now ->
        {:error, :expired_token}

      not is_integer(claims["iat"]) or claims["iat"] > now + 60 ->
        {:error, :invalid_issued_at}

      true ->
        :ok
    end
  end

  defp public_keys do
    case KeyValueStore.get(@cache_key) do
      keys when is_list(keys) -> {:ok, keys}
      _ -> fetch_public_keys()
    end
  end

  defp fetch_public_keys do
    case Req.get(@public_keys_url, connect_options: [timeout: 5000], receive_timeout: 5000, retry: false) do
      {:ok, %{status: 200, body: %{"keys" => keys}} = response} when is_list(keys) ->
        ttl = public_keys_ttl(response)
        if ttl > 0, do: KeyValueStore.put(@cache_key, keys, ttl: ttl)
        {:ok, keys}

      _ ->
        {:error, :public_keys_unavailable}
    end
  end

  defp public_keys_ttl(response) do
    cache_control = response |> Req.Response.get_header("cache-control") |> Enum.join(",")
    age = response |> Req.Response.get_header("age") |> List.first("0")

    with false <- String.contains?(cache_control, ["no-store", "no-cache"]),
         [_, seconds] <- Regex.run(~r/(?:^|[,\s])max-age=(\d+)/, cache_control),
         {age, ""} <- Integer.parse(age) do
      max(min(String.to_integer(seconds) - age, 300), 0) * 1000
    else
      _ -> 0
    end
  end
end
