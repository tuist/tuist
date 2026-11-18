defmodule Atlas.OAuth.Clients do
  @moduledoc """
  Boruta clients adapter for Atlas. Only dynamic registration is supported —
  all OAuth clients (e.g. Claude Desktop / Code connecting to the MCP server)
  register themselves at runtime via RFC 7591.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Atlas.Audit
  alias Boruta.Ecto.Clients, as: EctoClients
  alias Boruta.Oauth.Clients

  @impl Clients
  def get_client(client_id), do: EctoClients.get_client(client_id)

  @impl Clients
  def public!, do: EctoClients.public!()

  @impl Clients
  def authorized_scopes(client), do: EctoClients.authorized_scopes(client)

  @impl Clients
  def get_client_by_did(did), do: EctoClients.get_client_by_did(did)

  @impl Boruta.Openid.Clients
  def create_client(registration_params) do
    registration_params
    |> EctoClients.create_client()
    |> tap(fn
      {:ok, client} ->
        client_map = Map.from_struct(client)

        Audit.record("oauth_client.registered", %{
          target_type: "oauth_client",
          target_id: to_string(Map.get(client_map, :id)),
          target_label: Map.get(client_map, :name) || Map.get(client_map, :client_id),
          metadata:
            %{"client_id" => Map.get(client_map, :client_id)}
            |> maybe_put("redirect_uris", Map.get(client_map, :redirect_uris))
        })

      _ ->
        :ok
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl Clients
  def list_clients_jwk, do: EctoClients.list_clients_jwk()

  @impl Boruta.Openid.Clients
  # Boruta refreshes a key by fetching the client's `jwks_uri` with an
  # unguarded HTTP GET whenever a client assertion fails to verify, so a stored
  # URI would let anyone holding a client ID make the server request it.
  def refresh_jwk_from_jwks_uri(_client_id), do: {:error, "JWK refresh from JWKS URI not supported"}
end
