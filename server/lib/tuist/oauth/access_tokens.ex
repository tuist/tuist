defmodule Tuist.OAuth.AccessTokens do
  @moduledoc false
  @behaviour Boruta.Oauth.AccessTokens

  import Boruta.Config, only: [repo: 0]
  import Ecto.Query, only: [from: 2]

  alias Boruta.Ecto.Errors
  alias Boruta.Ecto.OauthMapper
  alias Boruta.Ecto.Token
  alias Boruta.Ecto.TokenStore
  alias Boruta.Oauth
  alias Boruta.Oauth.AccessTokens
  alias Boruta.Oauth.Client
  alias Tuist.OAuth.Clients

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
  def create(%{client: %Client{id: client_id, access_token_ttl: access_token_ttl}, scope: scope} = params, options) do
    sub = params[:sub]
    state = params[:state]
    redirect_uri = params[:redirect_uri]
    previous_token = params[:previous_token]
    previous_code = params[:previous_code]
    resource_owner = params[:resource_owner]
    agent_token = params[:agent_token]

    authorization_details =
      params[:authorization_details] || (resource_owner && resource_owner.authorization_details)

    token_attributes = %{
      client_id: client_id,
      sub: sub,
      redirect_uri: redirect_uri,
      state: state,
      scope: scope,
      access_token_ttl: access_token_ttl,
      previous_token: previous_token,
      previous_code: previous_code,
      authorization_details: authorization_details,
      agent_token: agent_token
    }

    changeset =
      apply(
        Token,
        changeset_method(options),
        [%Token{resource_owner: resource_owner}, token_attributes]
      )

    with {:ok, token} <- repo().insert(changeset),
         {:ok, token} <- token |> to_oauth_schema() |> TokenStore.put() do
      {:ok, token}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        error_message = Errors.message_from_changeset(changeset)

        {:error, "Could not create access token : #{error_message}"}
    end
  end

  defp changeset_method(refresh_token: true), do: :changeset_with_refresh_token
  defp changeset_method(_options), do: :changeset

  # Custom to_oauth_schema function that fetches client from Tuist.OAuth.Clients
  # instead of using preloaded associations
  defp to_oauth_schema(%Token{} = token) do
    client = Clients.get_client(token.client_id)
    token |> OauthMapper.to_oauth_schema() |> Map.put(:client, client)
  end

  @impl AccessTokens
  def revoke(%Oauth.Token{client: client, value: value}) do
    with %Token{} = token <- repo().get_by(Token, client_id: client.id, value: value),
         {:ok, token} <-
           token
           |> Token.revoke_changeset()
           |> repo().update() do
      TokenStore.invalidate(to_oauth_schema(token))
    else
      nil -> {:error, "Token not found."}
      error -> error
    end
  end

  @impl AccessTokens
  def revoke_refresh_token(%Oauth.Token{client: client, value: value}) do
    with %Token{} = token <- repo().get_by(Token, client_id: client.id, value: value),
         {:ok, token} <-
           token
           |> Token.revoke_refresh_token_changeset()
           |> repo().update() do
      TokenStore.invalidate(to_oauth_schema(token))
    else
      nil -> {:error, "Token not found."}
      error -> error
    end
  end
end
