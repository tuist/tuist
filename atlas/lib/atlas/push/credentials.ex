defmodule Atlas.Push.Credentials do
  @moduledoc """
  Per-node cache of provider authentication.

  APNs provider JWTs are reused for 50 minutes: Apple rejects tokens older than an
  hour and refreshes more frequent than every 20 minutes. FCM OAuth access tokens
  are reused until five minutes before expiry. Entries are keyed by the
  credential identity, so rotated keys never reuse stale tokens.

  Hits read ETS directly. Misses take a node-local lock per key and recheck the
  cache, so concurrent deliveries do not stampede the token endpoint, while the
  token is still generated in the calling process. This process only owns the
  table. Nothing is persisted, and the cache holds no device tokens.
  """
  use GenServer

  alias Atlas.Push.Config

  @table __MODULE__
  @apns_ttl_seconds 50 * 60
  @fcm_scope "https://www.googleapis.com/auth/firebase.messaging"
  @fcm_token_url "https://oauth2.googleapis.com/token"
  @fcm_refresh_margin_seconds 300

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def apns_token(%{team_id: team_id, key_id: key_id} = apns) do
    fetch({:apns, team_id, key_id}, fn -> {:ok, sign_apns(apns), @apns_ttl_seconds} end)
  end

  def fcm_token(%{project_id: project_id, client_email: email} = fcm) do
    fetch({:fcm, project_id, email}, fn -> request_fcm_token(fcm) end)
  end

  @doc "Drop a cached credential after the provider rejects it as expired."
  def invalidate(:apns, %{team_id: team_id, key_id: key_id}), do: :ets.delete(@table, {:apns, team_id, key_id})

  def invalidate(:fcm, %{project_id: project_id, client_email: email}),
    do: :ets.delete(@table, {:fcm, project_id, email})

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  defp fetch(key, generate) do
    case cached(key) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        :global.trans({{__MODULE__, key}, self()}, fn -> fetch_locked(key, generate) end, [node()])
    end
  end

  defp fetch_locked(key, generate) do
    with :miss <- cached(key),
         {:ok, value, ttl} <- generate.() do
      :ets.insert(@table, {key, value, now() + ttl})
      {:ok, value}
    end
  end

  defp cached(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] -> if expires_at > now(), do: {:ok, value}, else: :miss
      [] -> :miss
    end
  end

  defp sign_apns(%{team_id: team_id, key_id: key_id, private_key: private_key}) do
    private_key
    |> JOSE.JWK.from_pem()
    |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => key_id}, %{"iss" => team_id, "iat" => now()})
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp request_fcm_token(%{client_email: email, private_key: private_key}) do
    issued_at = now()

    {_, assertion} =
      private_key
      |> JOSE.JWK.from_pem()
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, %{
        "iss" => email,
        "scope" => @fcm_scope,
        "aud" => @fcm_token_url,
        "iat" => issued_at,
        "exp" => issued_at + 3600
      })
      |> JOSE.JWS.compact()

    request =
      Keyword.merge(
        [
          form: [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion],
          retry: false,
          redirect: false,
          receive_timeout: 10_000
        ],
        Config.req_options()
      )

    case Req.post(@fcm_token_url, request) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}}
      when is_binary(token) and is_integer(expires_in) and expires_in > @fcm_refresh_margin_seconds ->
        {:ok, token, expires_in - @fcm_refresh_margin_seconds}

      {:ok, %Req.Response{status: status}} when status in [400, 401, 403] ->
        {:error, :fcm_credentials_rejected}

      _ ->
        {:error, :fcm_token_unavailable}
    end
  end

  defp now, do: System.system_time(:second)
end
