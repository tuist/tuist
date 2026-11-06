defmodule Pulse.Auth.SharedSecret do
  @moduledoc """
  Per-tenant Bearer-token authentication. HTTP Basic credentials are accepted
  too, with the tenant as username and the token as password. A minimal but real auth surface
  suitable for prod until Pulse grows a real accounts service.

  Tokens are configured as:

      config :pulse, Pulse.Auth,
        module: Pulse.Auth.SharedSecret,
        tokens: %{"acme" => "sha256$<hex>", "beta" => "sha256$<hex>"}

  Values are of the form `"<algo>$<hex>"`. Only `sha256` is accepted today.
  Comparison is constant-time (`Plug.Crypto.secure_compare/2`) so token
  presence cannot be inferred from response timing.

  A tenant with no configured token is rejected as `:unknown_tenant`. Empty
  tokens are rejected as `:invalid_token` so an accidentally-blank env var
  cannot turn into "auth off for this tenant".
  """

  @behaviour Pulse.Auth

  alias Plug.Conn
  alias Pulse.Runtime

  @impl Pulse.Auth
  def verify(conn, tenant) when is_binary(tenant) do
    with {:ok, presented} <- extract_token(conn, tenant),
         {:ok, stored_hashes} <- fetch_stored_hashes(tenant) do
      compare_hash(presented, stored_hashes)
    end
  end

  # Basic credentials carry the token as the password and authorize only the
  # tenant named by their username, the Grafana Cloud convention.
  defp extract_token(conn, tenant) do
    case Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 ->
        {:ok, token}

      ["bearer " <> token] when byte_size(token) > 0 ->
        {:ok, token}

      _ ->
        case Pulse.Auth.basic_credentials(conn) do
          {:ok, ^tenant, password} -> {:ok, password}
          {:ok, _other, _password} -> {:error, :invalid_token}
          :error -> {:error, :missing_token}
        end
    end
  end

  # Configured tokens win; otherwise an active registry record's hashes
  # (`Pulse.Tenants`), several of which may be valid during rotation.
  defp fetch_stored_hashes(tenant) do
    tokens =
      case Runtime.get_env(:pulse, Pulse.Auth) do
        nil -> %{}
        env -> Keyword.get(env, :tokens, %{})
      end

    case Map.fetch(tokens, tenant) do
      {:ok, "sha256$" <> hex} when byte_size(hex) == 64 ->
        {:ok, [hex]}

      {:ok, _malformed} ->
        {:error, :invalid_token}

      :error ->
        case Pulse.Tenants.token_hashes(tenant) do
          {:ok, []} -> {:error, :unknown_tenant}
          {:ok, hashes} -> {:ok, Enum.map(hashes, fn "sha256$" <> hex -> hex end)}
          {:error, _} = error -> error
        end
    end
  end

  # Every stored hash is compared, so timing does not reveal which matched.
  defp compare_hash(presented, stored_hexes) do
    computed_hex =
      :sha256
      |> :crypto.hash(presented)
      |> Base.encode16(case: :lower)

    if Enum.reduce(stored_hexes, false, &(Plug.Crypto.secure_compare(computed_hex, &1) or &2)) do
      :ok
    else
      {:error, :invalid_token}
    end
  end
end
