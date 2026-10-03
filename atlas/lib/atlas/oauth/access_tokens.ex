defmodule Atlas.OAuth.AccessTokens do
  @moduledoc """
  Boruta access token adapter for Atlas.

  Mirrors `Boruta.Ecto.AccessTokens` so tokens are minted through
  `Atlas.OAuth.TokenGenerator` (Guardian JWTs) and read back with the
  Atlas client adapter. Every attribute Boruta hands us has to be
  persisted, `resource` included: the refresh grant compares the
  `resource` on the incoming request against the one stored on the token
  it is refreshing, so dropping it turns every refresh into
  `invalid_target`.
  """
  @behaviour Boruta.Oauth.AccessTokens

  import Boruta.Config, only: [repo: 0]
  import Ecto.Query, only: [from: 2]

  alias Atlas.OAuth.Clients
  alias Boruta.Ecto.Errors
  alias Boruta.Ecto.OauthMapper
  alias Boruta.Ecto.Token
  alias Boruta.Ecto.TokenStore
  alias Boruta.Oauth
  alias Boruta.Oauth.AccessTokens
  alias Boruta.Oauth.Client

  @impl AccessTokens
  def get_by(attrs) do
    case get_by(:from_cache, attrs) do
      {:ok, token} -> token
      {:error, _reason} -> get_by(:from_database, attrs)
    end
  end

  defp get_by(:from_cache, attrs), do: TokenStore.get(attrs)

  defp get_by(:from_database, value: value) do
    with %Token{} = token <-
           repo().one(
             from t in Token,
               where: t.type == "access_token" and t.value == ^value
           ),
         {:ok, token} <- token |> to_oauth_schema() |> TokenStore.put() do
      token
    end
  end

  defp get_by(:from_database, refresh_token: refresh_token) do
    with %Token{} = token <-
           repo().one(
             from t in Token,
               where: t.type == "access_token" and t.refresh_token == ^refresh_token
           ),
         {:ok, token} <- token |> to_oauth_schema() |> TokenStore.put() do
      token
    end
  end

  @impl AccessTokens
  def create(%{client: %Client{id: client_id, access_token_ttl: ttl}, scope: scope} = params, options) do
    token_attributes = %{
      client_id: client_id,
      sub: params[:sub],
      redirect_uri: params[:redirect_uri],
      state: params[:state],
      scope: scope,
      resource: params[:resource],
      access_token_ttl: ttl,
      previous_token: params[:previous_token],
      previous_code: params[:previous_code],
      authorization_details:
        params[:authorization_details] ||
          (params[:resource_owner] && params[:resource_owner].authorization_details),
      agent_token: params[:agent_token]
    }

    changeset =
      apply(
        Token,
        changeset_method(options),
        [%Token{resource_owner: params[:resource_owner]}, token_attributes]
      )

    with {:ok, token} <- repo().insert(changeset),
         {:ok, token} <- token |> to_oauth_schema() |> TokenStore.put() do
      {:ok, token}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not create access token : #{Errors.message_from_changeset(changeset)}"}
    end
  end

  defp changeset_method(refresh_token: true), do: :changeset_with_refresh_token
  defp changeset_method(_), do: :changeset

  defp to_oauth_schema(%Token{} = token) do
    client = Clients.get_client(token.client_id)
    token |> OauthMapper.to_oauth_schema() |> Map.put(:client, client)
  end

  @impl AccessTokens
  def revoke(%Oauth.Token{client: client, value: value}) do
    with %Token{} = token <- repo().get_by(Token, client_id: client.id, value: value),
         {:ok, token} <- token |> Token.revoke_changeset() |> repo().update() do
      TokenStore.invalidate(to_oauth_schema(token))
    else
      nil -> {:error, "Token not found."}
      error -> error
    end
  end

  @impl AccessTokens
  def revoke_refresh_token(%Oauth.Token{client: client, value: value}) do
    with %Token{} = token <- repo().get_by(Token, client_id: client.id, value: value),
         {:ok, token} <- token |> Token.revoke_refresh_token_changeset() |> repo().update() do
      TokenStore.invalidate(to_oauth_schema(token))
    else
      nil -> {:error, "Token not found."}
      error -> error
    end
  end
end
