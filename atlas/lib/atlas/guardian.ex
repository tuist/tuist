defmodule Atlas.Guardian do
  @moduledoc """
  Guardian implementation that issues and verifies JWTs for the Atlas
  MCP OAuth flow. Tokens encode the originating user id and granted
  scopes; verifying a token returns the `Atlas.Users.User` it was issued for.
  """

  use Guardian, otp_app: :atlas

  alias Atlas.OAuth.AccessTokens
  alias Atlas.Users
  alias Atlas.Users.User
  alias Boruta.Oauth.Token

  def subject_for_token(%User{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :invalid_subject}

  def resource_from_claims(%{"sub" => id}) do
    case Users.get_user(id) do
      nil -> {:error, :resource_not_found}
      %User{} = user -> {:ok, user}
    end
  end

  def after_encode_and_sign(resource, claims, token, _options) do
    with {:ok, _} <- Guardian.DB.after_encode_and_sign(resource, claims["typ"], claims, token) do
      {:ok, token}
    end
  end

  def on_verify(claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_verify(claims, token),
         :ok <- verify_oauth_token(claims, token) do
      {:ok, claims}
    end
  end

  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _options) do
    with {:ok, _, _} <- Guardian.DB.on_refresh({old_token, old_claims}, {new_token, new_claims}) do
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    end
  end

  def on_revoke(claims, token, _options \\ []) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end

  # OAuth JWTs were historically not stored by Guardian.DB (only refresh
  # tokens are). Keep existing JWTs usable during rolling upgrades while
  # enforcing Boruta revocation/expiry directly against shared database state.
  defp verify_oauth_token(%{"typ" => "access_token"}, value) do
    with %Token{} = token <- AccessTokens.get_by(value: value),
         :ok <- Token.ensure_valid(token) do
      :ok
    else
      _ -> {:error, :token_not_found}
    end
  end

  defp verify_oauth_token(_claims, _value), do: :ok
end
