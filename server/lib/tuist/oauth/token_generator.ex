defmodule Tuist.OAuth.TokenGenerator do
  @moduledoc """
  Custom token generator for Boruta that uses Guardian to generate JWT tokens.

  OAuth tokens are generated as scoped AuthenticatedAccount JWTs with
  all_projects access. The scopes from the OAuth grant determine what
  operations the token can perform. A `user_id` claim is included so
  that cross-organization project listing can resolve the originating user.
  A `client_id` claim lets persistent event subscriptions recheck the grant.
  An `sso` claim records the single sign-on the authorizing browser session
  proved, so refreshing the tokens can check the user's SSO-enforcing
  organizations again.
  """

  @behaviour Boruta.Oauth.TokenGenerator

  alias Boruta.Ecto.Token
  alias Boruta.Oauth.ResourceOwner
  alias Boruta.Oauth.TokenGenerator
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Cache
  alias Tuist.OAuth.Clients
  alias Tuist.Repo

  @impl TokenGenerator
  def generate(token_type, %Token{sub: sub, client_id: client_id, scope: scope} = token) do
    generate_user_token(token_type, sub, client_id, scope, sso_claims(token))
  end

  # Boruta generates an authorization code with the resource owner the
  # authorize request passed, the tokens exchanged for a code with that code
  # as `previous_code`, and refreshed tokens with the access token they replace
  # as `previous_token`. The previous values come from Boruta's own token
  # store, which holds only tokens this module generated, so their claims are
  # read without verifying again (the access token may have expired).
  defp sso_claims(%Token{resource_owner: %ResourceOwner{extra_claims: %{"sso" => sso}}}), do: %{"sso" => sso}

  defp sso_claims(%Token{previous_token: previous}) when is_binary(previous), do: previous_sso_claims(previous)
  defp sso_claims(%Token{previous_code: previous}) when is_binary(previous), do: previous_sso_claims(previous)
  defp sso_claims(_token), do: %{}

  defp previous_sso_claims(previous) do
    case Tuist.Guardian.peek(previous) do
      %{claims: %{"sso" => sso}} -> %{"sso" => sso}
      _ -> %{}
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

  defp parse_user_id(sub) when is_binary(sub), do: Integer.parse(sub)
  defp parse_user_id(_sub), do: :error

  defp ttl_for(:access_token, client), do: client.access_token_ttl
  defp ttl_for(:refresh_token, client), do: client.refresh_token_ttl

  defp generate_user_token(token_type, sub, client_id, scope, sso_claims) do
    with {user_id, ""} <- parse_user_id(sub),
         user when not is_nil(user) <- User |> Repo.get(user_id) |> Repo.preload(:account),
         client when not is_nil(client) <- Clients.get_client(client_id) do
      scopes = parse_scopes(scope)

      claims = %{
        "type" => "account",
        "scopes" => scopes,
        "all_projects" => true,
        "user_id" => user.id,
        "client_id" => client_id,
        "preferred_username" => user.account.name,
        "email" => user.email
      }

      cache_subject = %AuthenticatedAccount{
        account: user.account,
        scopes: scopes,
        all_projects: true,
        issued_by: user
      }

      claims =
        claims
        |> Map.merge(sso_claims)
        |> Map.merge(Cache.embedded_cache_claims(cache_subject, recent: 5))

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

  @impl TokenGenerator
  def secret(client) do
    Boruta.TokenGenerator.secret(client)
  end

  @impl TokenGenerator
  def tx_code_input_mode, do: :numeric

  @impl TokenGenerator
  def tx_code_length, do: 6
end
