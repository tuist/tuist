defmodule Tuist.OAuth.Exchange do
  @moduledoc """
  Serializes one-time credential exchanges without forking Boruta's adapters.

  Capture callbacks defer the HTTP response until the credential transaction
  commits. The transaction covers validation, replacement creation and revocation.
  A lost response after commit still consumes the credential; this is not token
  delivery recovery or revocation of already-issued JWTs. All grant-serving
  replicas must run this wrapper before relying on exchange serialization;
  legacy Boruta-only issuers do not participate in its lock protocol.
  """
  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Error
  alias Tuist.Repo

  def token(conn, oauth_module, application) do
    case credential_query(conn.params) do
      nil ->
        oauth_module.token(conn, application)

      query ->
        exchange(conn, oauth_module, application, query)
    end
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :lock_not_available do
        application.token_error(conn, %Error{
          status: :service_unavailable,
          error: :temporarily_unavailable,
          error_description: "OAuth exchange temporarily unavailable."
        })
      else
        reraise error, __STACKTRACE__
      end
  end

  def token_success(_conn, response), do: {:success, response}
  def token_error(_conn, error), do: {:error, error}

  defp exchange(conn, oauth_module, application, query) do
    transaction =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL lock_timeout = '5s'")
        Repo.one(from(t in query, select: t.id, lock: "FOR UPDATE"))
        capture_exchange(conn, oauth_module)
      end)

    result =
      case transaction do
        {:ok, result} -> result
        {:error, result} -> result
      end

    case result do
      {:success, response} -> application.token_success(conn, response)
      {:error, error} -> application.token_error(conn, error)
    end
  end

  defp capture_exchange(conn, oauth_module) do
    case oauth_module.token(conn, __MODULE__) do
      # Boruta intentionally revokes a code's descendant on reuse.
      {:error, %Error{error: :invalid_grant}} = error -> error
      {:error, _} = error -> Repo.rollback(error)
      success -> success
    end
  end

  defp credential_query(%{"grant_type" => "authorization_code", "code" => code}) when is_binary(code) do
    from(t in Token, where: t.type == "code" and t.value == ^code)
  end

  defp credential_query(%{"grant_type" => "refresh_token", "refresh_token" => token}) when is_binary(token) do
    from(t in Token, where: t.type == "access_token" and t.refresh_token == ^token)
  end

  defp credential_query(_params), do: nil
end
