defmodule Condukt.MCP.Auth do
  @moduledoc false

  # Resolves a `Condukt.MCP.Server` `:auth` declaration into a list of
  # request headers and (for client_credentials) a token cache state.
  #
  # The same secret-reference shapes used by `Condukt.Secrets` are
  # accepted in the second position of `{:bearer, ref}`:
  #
  #   * `{:env, "VAR"}` reads from the host process environment
  #   * `{:static, "value"}` uses a literal value (mostly for tests)
  #   * `{:op, "op://..."}` resolves through the 1Password CLI
  #   * `{provider_module, opts}` for a custom `Condukt.SecretProvider`
  #
  # Tests can inject `fetch_env: fn` to avoid touching the host
  # environment.

  alias Condukt.Secrets.Providers

  @provider_aliases %{
    env: Providers.Env,
    static: Providers.Static,
    op: Providers.OnePassword,
    one_password: Providers.OnePassword
  }

  @doc """
  Resolves the auth declaration into a list of `{header_name, value}`
  tuples that should be added to every outgoing request.

  Returns `{:ok, headers, state}` where `state` is opaque metadata used
  by `refresh/2` to refresh expired tokens (currently only meaningful
  for client_credentials).
  """
  def resolve(nil, _opts), do: {:ok, [], %{}}

  def resolve({:bearer, ref}, opts) do
    case load_secret(ref, opts) do
      {:ok, token} -> {:ok, [{"authorization", "Bearer " <> token}], %{kind: :bearer, value: token}}
      {:error, _} = err -> err
    end
  end

  def resolve({:client_credentials, oauth_opts}, opts) do
    with {:ok, token_url} <- resolve_credential(oauth_opts, :token_url, opts),
         {:ok, client_id} <- resolve_credential(oauth_opts, :client_id, opts),
         {:ok, client_secret} <- resolve_credential(oauth_opts, :client_secret, opts) do
      fetch_token(token_url, oauth_opts, client_id, client_secret, opts)
    end
  end

  def resolve(other, _opts), do: {:error, {:invalid_auth, other}}

  @doc """
  Refreshes a previously resolved auth state when a server returns 401.
  Currently only client_credentials supports refresh; bearer tokens are
  returned unchanged.
  """
  def refresh(%{kind: :bearer} = state, _opts) do
    {:ok, [{"authorization", "Bearer " <> state.value}], state}
  end

  def refresh(%{kind: :client_credentials} = state, opts) do
    fetch_token(state.token_url, state.oauth_opts, state.client_id, state.client_secret, opts)
  end

  def refresh(state, _opts), do: {:ok, [], state}

  @doc """
  Returns the resolved bearer token value (if any) so callers can
  register it for redaction.
  """
  def secret_value(%{kind: :bearer, value: value}), do: value
  def secret_value(%{kind: :client_credentials, value: value}) when is_binary(value), do: value
  def secret_value(_), do: nil

  defp resolve_credential(oauth_opts, key, opts) do
    cond do
      value = Keyword.get(oauth_opts, key) ->
        {:ok, to_string(value)}

      env_name = Keyword.get(oauth_opts, :"#{key}_env") ->
        load_secret({:env, env_name}, opts)

      static = Keyword.get(oauth_opts, :"#{key}_static") ->
        {:ok, to_string(static)}

      true ->
        {:error, {:missing_credential, key}}
    end
  end

  defp fetch_token(token_url, oauth_opts, client_id, client_secret, opts) do
    scope = Keyword.get(oauth_opts, :scope)
    request_fn = Keyword.get(opts, :token_request, &default_token_request/4)

    case request_fn.(token_url, client_id, client_secret, scope) do
      {:ok, %{"access_token" => token} = body} ->
        state = %{
          kind: :client_credentials,
          value: token,
          token_url: token_url,
          oauth_opts: oauth_opts,
          client_id: client_id,
          client_secret: client_secret,
          token_type: Map.get(body, "token_type", "Bearer")
        }

        {:ok, [{"authorization", "Bearer " <> token}], state}

      {:ok, body} ->
        {:error, {:invalid_token_response, body}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  defp default_token_request(token_url, client_id, client_secret, scope) do
    body =
      %{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
      |> maybe_put("scope", scope)
      |> URI.encode_query()

    headers = [{"content-type", "application/x-www-form-urlencoded"}, {"accept", "application/json"}]

    case Req.post(token_url, headers: headers, body: body, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp load_secret({alias, value}, opts) when is_atom(alias) and is_map_key(@provider_aliases, alias) do
    provider = Map.fetch!(@provider_aliases, alias)
    provider_opts = provider_opts(alias, value, opts)
    provider.load(provider_opts)
  end

  defp load_secret({module, provider_opts}, _opts) when is_atom(module) and is_list(provider_opts) do
    module.load(provider_opts)
  end

  defp load_secret(other, _opts), do: {:error, {:invalid_secret_ref, other}}

  defp provider_opts(:env, name, opts) do
    base = [name: to_string(name)]

    case Keyword.get(opts, :fetch_env) do
      nil -> base
      fun -> Keyword.put(base, :fetch_env, fun)
    end
  end

  defp provider_opts(:static, value, _opts), do: [value: to_string(value)]
  defp provider_opts(:op, ref, _opts), do: [ref: to_string(ref)]
  defp provider_opts(:one_password, ref, _opts), do: [ref: to_string(ref)]
end
