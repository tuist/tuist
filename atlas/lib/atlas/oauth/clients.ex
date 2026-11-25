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
  alias Boruta.Oauth.Client
  alias Boruta.Oauth.Clients

  # Boruta's registration stores whatever grants the anonymous registrant lists,
  # and every grant it implements when none are listed. Implicit would issue MCP
  # tokens without PKCE, so clients only get the grants Atlas advertises.
  @supported_grant_types ["authorization_code", "refresh_token"]

  @impl Clients
  def get_client(client_id), do: client_id |> EctoClients.get_client() |> restrict_grant_types()

  @impl Clients
  def public!, do: EctoClients.public!()

  @impl Clients
  def authorized_scopes(client), do: EctoClients.authorized_scopes(client)

  @impl Clients
  def get_client_by_did(did), do: did |> EctoClients.get_client_by_did() |> restrict_grant_types()

  @impl Boruta.Openid.Clients
  def create_client(registration_params) do
    registration_params
    |> Map.update(:supported_grant_types, @supported_grant_types, &supported_grant_types/1)
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

  # Clients registered before this restriction still carry Boruta's default list.
  defp restrict_grant_types(%Client{supported_grant_types: grant_types} = client),
    do: %{client | supported_grant_types: supported_grant_types(grant_types)}

  defp restrict_grant_types(other), do: other

  defp supported_grant_types(grant_types) when is_list(grant_types),
    do: Enum.filter(grant_types, &(&1 in @supported_grant_types))

  defp supported_grant_types(_grant_types), do: @supported_grant_types

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
