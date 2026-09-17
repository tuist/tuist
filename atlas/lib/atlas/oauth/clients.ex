defmodule Atlas.OAuth.Clients do
  @moduledoc """
  Boruta clients adapter for Atlas. Only dynamic registration is supported —
  all OAuth clients (e.g. Claude Desktop / Code connecting to the MCP server)
  register themselves at runtime via RFC 7591.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

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
  def create_client(registration_params), do: EctoClients.create_client(registration_params)

  @impl Clients
  def list_clients_jwk, do: EctoClients.list_clients_jwk()

  @impl Boruta.Openid.Clients
  def refresh_jwk_from_jwks_uri(client_id), do: EctoClients.refresh_jwk_from_jwks_uri(client_id)
end
