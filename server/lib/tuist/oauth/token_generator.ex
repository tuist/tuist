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
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.AuthenticatedService
  alias Tuist.Accounts.User
  alias Tuist.Cache
  alias Tuist.OAuth.Clients
  alias Tuist.Repo

  @impl TokenGenerator
  def generate(token_type, %Boruta.Ecto.Token{sub: sub, client_id: client_id, scope: scope}) do
    if Clients.service_client?(client_id) do
      generate_service_token(token_type, client_id, scope)
    else
      generate_user_token(token_type, sub, client_id, scope)
    end
  end

  @default_user_scopes [
    "account:cache:read",
    "account:cache:write",
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

  defp parse_service_scopes(nil), do: []
  defp parse_service_scopes(""), do: []
  defp parse_service_scopes(scope), do: String.split(scope, " ", trim: true)

  defp parse_user_id(sub) when is_binary(sub), do: Integer.parse(sub)
  defp parse_user_id(_sub), do: :error

  defp ttl_for(:access_token, client), do: client.access_token_ttl
  defp ttl_for(:refresh_token, client), do: client.refresh_token_ttl

  defp generate_user_token(token_type, sub, client_id, scope) do
    with {user_id, ""} <- parse_user_id(sub),
         user when not is_nil(user) <- User |> Repo.get(user_id) |> Repo.preload(:account),
         client when not is_nil(client) <- Clients.get_client(client_id) do
      scopes = parse_scopes(scope)

      claims = %{
        "type" => "account",
        "scopes" => scopes,
        "all_projects" => true,
        "user_id" => user.id,
        "preferred_username" => user.account.name,
        "email" => user.email
      }

      cache_subject = %AuthenticatedAccount{
        account: user.account,
        scopes: scopes,
        all_projects: true,
        issued_by: user
      }

      claims = Map.merge(claims, Cache.embedded_cache_claims(cache_subject, recent: 5))

      {:ok, jwt_token, _claims} =
        Tuist.Guardian.encode_and_sign(user.account, claims,
          token_type: Atom.to_string(token_type),
          ttl: {ttl_for(token_type, client), :second}
        )

      jwt_token
    else
      _ -> nil
    end
  end

  defp generate_service_token(token_type, client_id, scope) do
    with true <- Clients.service_client?(client_id),
         client when not is_nil(client) <- Clients.get_client(client_id) do
      scopes = parse_service_scopes(scope)
      service = %AuthenticatedService{client_id: client_id, scopes: scopes}

      claims = %{
        "type" => "service",
        "client_id" => client_id,
        "scopes" => scopes
      }

      {:ok, jwt_token, _claims} =
        Tuist.Guardian.encode_and_sign(service, claims,
          token_type: Atom.to_string(token_type),
          ttl: {ttl_for(token_type, client), :second}
        )

      jwt_token
    else
      _ -> nil
    end
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
