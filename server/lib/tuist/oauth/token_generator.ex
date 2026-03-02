defmodule Tuist.OAuth.TokenGenerator do
  @moduledoc """
  Custom token generator for Boruta that uses Guardian to generate JWT tokens.
  """

  @behaviour Boruta.Oauth.TokenGenerator

  alias Boruta.Oauth.TokenGenerator
  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias Tuist.OAuth.Clients
  alias Tuist.Repo

  @scoped_grants ["mcp"]

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

      if has_scoped_grant?(scopes) do
        generate_scoped_token(user, scopes, token_type, ttl)
      else
        generate_user_token(user, token_type, ttl)
      end
    end
  end

  defp generate_user_token(user, token_type, ttl) do
    {:ok, jwt_token, _claims} =
      Authentication.encode_and_sign(user, %{"preferred_username" => user.account.name, "email" => user.email},
        token_type: Atom.to_string(token_type),
        ttl: {ttl, :second}
      )

    jwt_token
  end

  defp generate_scoped_token(user, scopes, token_type, ttl) do
    claims = %{
      "type" => "account",
      "scopes" => scopes,
      "all_projects" => true,
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

  defp parse_scopes(nil), do: []
  defp parse_scopes(""), do: []
  defp parse_scopes(scope), do: String.split(scope, " ", trim: true)

  defp has_scoped_grant?(scopes) do
    Enum.any?(scopes, &(&1 in @scoped_grants))
  end

  @impl TokenGenerator
  def secret(client) do
    Boruta.TokenGenerator.secret(client)
  end

  @impl TokenGenerator
  def tx_code_input_mode, do: :numeric

  @impl TokenGenerator
  def tx_code_length, do: 6
end
