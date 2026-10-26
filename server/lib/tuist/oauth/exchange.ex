defmodule Tuist.OAuth.Exchange do
  @moduledoc """
  Serializes authorization-code and refresh-token exchanges using Boruta's
  request parser, authorization protocol and response conversion.

  Parse exactly once before taking a database connection: inline request objects
  and stored request references select the credential that Boruta redeems.
  External request URIs are rejected before Boruta can fetch them from this
  unauthenticated endpoint. Responses
  are deferred until the transaction commits. The transaction covers validation,
  replacement creation and revocation. Refresh requests retain the bounded,
  encrypted response replay used by the token endpoint; this is not unbounded
  delivery recovery or revocation of already-issued JWTs. All grant-serving replicas must run this wrapper;
  legacy Boruta-only issuers do not participate in its lock protocol.
  """
  import Ecto.Query

  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Authorization
  alias Boruta.Oauth.Authorization.Client, as: ClientAuthorization
  alias Boruta.Oauth.AuthorizationCodeRequest
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.RefreshTokenRequest
  alias Boruta.Oauth.Request
  alias Boruta.Oauth.TokenResponse
  alias Tuist.Authentication.RefreshReplays
  alias Tuist.Repo

  @response_fields [:token_type, :access_token, :expires_in, :refresh_token, :id_token]

  def token(conn, application, opts \\ []) do
    result =
      with :ok <- allow_request_uri(conn),
           {:ok, request} <- Request.token_request(conn),
           :ok <- preflight_client(request) do
        authorize = Keyword.get(opts, :authorize, &Authorization.token/1)

        case credential_query(request) do
          nil -> authorize(request, authorize)
          query -> exchange(request, authorize, query)
        end
      end

    respond(conn, application, result)
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

  # Match Boruta's envelope precedence by key presence, including malformed
  # higher-priority carriers. Do not fall back to a lower request envelope.
  defp allow_request_uri(%{query_params: %{"request" => _}}), do: :ok

  defp allow_request_uri(%{query_params: %{"request_uri" => "urn:ietf:params:oauth:request_uri:" <> _}}), do: :ok

  defp allow_request_uri(%{query_params: %{"request_uri" => _}}), do: external_request_uri_error()
  defp allow_request_uri(%{body_params: %{"request" => _}}), do: :ok
  defp allow_request_uri(%{body_params: %{"request_uri" => _}}), do: external_request_uri_error()
  defp allow_request_uri(_conn), do: :ok

  defp external_request_uri_error do
    {:error,
     %Error{
       status: :bad_request,
       error: :invalid_request,
       error_description: "External request_uri is not supported at the token endpoint; use an inline request."
     }}
  end

  defp preflight_client(%AuthorizationCodeRequest{client_authentication: %{type: "jwt"} = source} = request) do
    client_authorized(
      ClientAuthorization.authorize(
        id: request.client_id,
        source: source,
        redirect_uri: request.redirect_uri,
        grant_type: request.grant_type,
        code_verifier: request.code_verifier
      )
    )
  end

  defp preflight_client(%RefreshTokenRequest{client_authentication: %{type: "jwt"} = source} = request) do
    client_authorized(
      ClientAuthorization.authorize(
        id: request.client_id,
        source: source,
        grant_type: request.grant_type
      )
    )
  end

  defp preflight_client(_request), do: :ok
  defp client_authorized({:ok, _client}), do: :ok
  defp client_authorized({:error, _} = error), do: error

  defp exchange(request, authorize, query) do
    transaction =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL lock_timeout = '5s'")

        redeem = fn ->
          Repo.one(from(t in query, select: t.id, lock: "FOR UPDATE"))
          authorize(request, authorize)
        end

        case replay_or_redeem(request, redeem) do
          # Boruta intentionally revokes a code's descendant on reuse.
          {:error, %Error{error: :invalid_grant}} = error -> error
          {:error, _} = error -> Repo.rollback(error)
          success -> success
        end
      end)

    case transaction do
      {:ok, result} -> result
      {:error, result} -> result
    end
  end

  defp replay_or_redeem(%RefreshTokenRequest{refresh_token: token} = request, redeem) when is_binary(token) do
    authentication = request.client_authentication || %{}

    credential =
      Enum.map_join(
        [request.client_id, authentication[:type], authentication[:value], request.scope],
        <<0>>,
        &to_string/1
      )

    result =
      RefreshReplays.exchange("oauth", token, credential, fn ->
        case redeem.() do
          {:success, response} ->
            data = response |> Map.take(@response_fields) |> Map.reject(fn {_key, value} -> is_nil(value) end)
            {:ok, data}

          error ->
            error
        end
      end)

    case result do
      {:ok, data} ->
        fields = Map.new(@response_fields, fn key -> {key, Map.get(data, key, Map.get(data, to_string(key)))} end)
        {:success, struct!(TokenResponse, fields)}

      error ->
        error
    end
  end

  defp replay_or_redeem(_request, redeem), do: redeem.()

  defp authorize(request, authorize) do
    with {:ok, tokens} <- authorize.(request),
         %TokenResponse{} = response <- TokenResponse.from_token(tokens) do
      {:success, response}
    else
      {:error, _} = error -> error
      _ -> {:error, :unexpected_authorization_result}
    end
  end

  defp respond(conn, application, {:success, response}), do: application.token_success(conn, response)
  defp respond(conn, application, {:error, %Error{} = error}), do: application.token_error(conn, error)

  defp respond(conn, application, {:error, reason}) do
    application.token_error(conn, %Error{
      status: :internal_server_error,
      error: :unknown_error,
      error_description: inspect(reason)
    })
  end

  defp credential_query(%AuthorizationCodeRequest{code: code}) when is_binary(code) do
    from(t in Token, where: t.type in ["code", "preauthorized_code"] and t.value == ^code)
  end

  defp credential_query(%RefreshTokenRequest{refresh_token: token}) when is_binary(token) do
    from(t in Token, where: t.type == "access_token" and t.refresh_token == ^token)
  end

  defp credential_query(_request), do: nil
end
