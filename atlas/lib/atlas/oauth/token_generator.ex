defmodule Atlas.OAuth.TokenGenerator do
  @moduledoc """
  Custom token generator for Boruta that mints Guardian JWT access tokens
  scoped to a single Atlas user. The `sub` claim is the user UUID; the
  `scopes` claim carries the granted OAuth scopes; `client_id` names the OAuth
  client the user approved, as RFC 9068 defines it, so the audit trail can tell
  which client acted.
  """

  @behaviour Boruta.Oauth.TokenGenerator

  alias Atlas.Guardian
  alias Atlas.Users
  alias Boruta.Ecto.Token
  alias Boruta.Oauth.TokenGenerator

  @default_scopes ["mcp"]

  @impl TokenGenerator
  def generate(:access_token = token_type, %Token{sub: sub, scope: scope, client_id: client_id} = token) do
    case Users.get_user(sub) do
      nil ->
        Boruta.TokenGenerator.generate(token_type, token)

      user ->
        ttl = ttl_for(token_type)
        scopes = parse_scopes(scope)

        claims = %{
          "scopes" => scopes,
          "email" => user.email,
          "client_id" => client_id
        }

        {:ok, jwt, _claims} =
          Guardian.encode_and_sign(user, claims,
            token_type: Atom.to_string(token_type),
            ttl: {ttl, :second}
          )

        jwt
    end
  end

  def generate(token_type, token), do: Boruta.TokenGenerator.generate(token_type, token)

  defp ttl_for(:access_token), do: 86_400

  defp parse_scopes(nil), do: @default_scopes
  defp parse_scopes(""), do: @default_scopes
  defp parse_scopes(scope), do: String.split(scope, " ", trim: true)

  @impl TokenGenerator
  def secret(client), do: Boruta.TokenGenerator.secret(client)

  @impl TokenGenerator
  def tx_code_input_mode, do: :numeric

  @impl TokenGenerator
  def tx_code_length, do: 6
end
