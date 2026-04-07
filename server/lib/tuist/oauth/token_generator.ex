defmodule Tuist.OAuth.TokenGenerator do
  @moduledoc """
  Custom token generator for Boruta that uses Guardian to generate JWT tokens.

  OAuth tokens are generated as scoped AuthenticatedAccount JWTs with
  all_projects access. The scopes from the OAuth grant determine what
  operations the token can perform. A `user_id` claim is included so
  that cross-organization project listing can resolve the originating user.
  """

  @behaviour Boruta.Oauth.TokenGenerator

  alias Boruta.Oauth.TokenGenerator
  alias Tuist.Accounts.User
  alias Tuist.OAuth.Clients
  alias Tuist.Repo

  @impl TokenGenerator
  def generate(token_type, %Boruta.Ecto.Token{sub: sub, client_id: client_id, scope: scope}) do
    user_id = String.to_integer(sub)

    with user when not is_nil(user) <- User |> Repo.get(user_id) |> Repo.preload(:account),
         client when not is_nil(client) <- Clients.get_client(client_id) do
      ttl =
        case token_type do
          :access_token -> client.access_token_ttl
          :refresh_token -> client.refresh_token_ttl
        end

      scopes = parse_scopes(scope)

      claims = %{
        "type" => "account",
        "scopes" => scopes,
        "all_projects" => true,
        "user_id" => user.id,
        "preferred_username" => user.account.name,
        "email" => user.email
      }

      {:ok, jwt_token, _claims} =
        Tuist.Guardian.encode_and_sign(user.account, claims,
          token_type: Atom.to_string(token_type),
          ttl: {ttl, :second}
        )

      jwt_token
    end
  end

  @default_user_scopes [
    "project:admin:read",
    "project:cache:read",
    "project:cache:write",
    "project:previews:read",
    "project:previews:write",
    "project:bundles:read",
    "project:bundles:write",
    "project:tests:read",
    "project:tests:write",
    "project:builds:read",
    "project:builds:write",
    "project:runs:read",
    "project:runs:write"
  ]

  defp parse_scopes(nil), do: @default_user_scopes
  defp parse_scopes(""), do: @default_user_scopes
  defp parse_scopes(scope), do: String.split(scope, " ", trim: true)

  @impl TokenGenerator
  def secret(client) do
    Boruta.TokenGenerator.secret(client)
  end

  @impl TokenGenerator
  def tx_code_input_mode, do: :numeric

  @impl TokenGenerator
  def tx_code_length, do: 6
end
