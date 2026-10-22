defmodule Tuist.OAuth.ExchangeTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Oauth.Error
  alias Boruta.Oauth.RefreshTokenRequest
  alias Boruta.Oauth.Request
  alias Boruta.Oauth.Token
  alias Tuist.Accounts.User
  alias Tuist.OAuth.Exchange
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defmodule Response do
    @moduledoc false
    def token_success(conn, _response) do
      send(self(), {:response_transaction, Repo.in_transaction?()})
      Plug.Conn.send_resp(conn, 200, "ok")
    end

    def token_error(conn, error) do
      send(self(), {:response_transaction, Repo.in_transaction?(), error})
      Plug.Conn.send_resp(conn, error.status, "error")
    end
  end

  test "authorization runs inside a transaction but HTTP succeeds only after commit" do
    assert %{status: 200, state: :sent} =
             exchange(connection(), fn _ ->
               send(self(), {:exchange_transaction, Repo.in_transaction?()})
               success()
             end)

    assert_receive {:exchange_transaction, true}
    assert_receive {:response_transaction, false}
  end

  test "a database lock timeout returns unavailable without invoking the grant or sending within a transaction" do
    expect(Repo, :query!, fn "SET LOCAL lock_timeout = '5s'" ->
      raise %Postgrex.Error{
        postgres: %{code: :lock_not_available, pg_code: "55P03", severity: "ERROR", message: "lock timeout"}
      }
    end)

    assert %{status: 503, state: :sent} = exchange(connection(), fn _ -> flunk("grant ran without its lock") end)
    assert_receive {:response_transaction, false, %Error{error: :temporarily_unavailable}}
  end

  test "a failed rotation rolls back replacement writes before sending an error" do
    assert %{status: 500} =
             exchange(connection(), fn _ ->
               user = AccountsFixtures.user_fixture()
               send(self(), {:new_user, user.id})
               {:error, %Error{error: :unknown_error, status: :internal_server_error, error_description: "unavailable"}}
             end)

    assert_receive {:new_user, id}
    assert Repo.get(User, id) == nil
    assert_receive {:response_transaction, false, _}
  end

  test "an unexpected authorization return rolls back before responding" do
    assert %{status: 500} =
             exchange(connection(), fn _ ->
               user = AccountsFixtures.user_fixture()
               send(self(), {:unexpected_user, user.id})
               :unexpected
             end)

    assert_receive {:unexpected_user, id}
    assert Repo.get(User, id) == nil

    assert_receive {:response_transaction, false,
                    %Error{error: :unknown_error, error_description: ":unexpected_authorization_result"}}
  end

  test "a refresh credential carried only by a request object is locked" do
    params = %{"grant_type" => "refresh_token", "refresh_token" => "request-token", "client_id" => Ecto.UUID.generate()}
    conn = connection(%{"request" => jwt(params)})

    assert %{status: 200} =
             exchange(conn, fn %RefreshTokenRequest{refresh_token: "request-token"} ->
               assert Repo.in_transaction?()
               success()
             end)
  end

  test "the lock follows Boruta's body and request precedence rather than merged query params" do
    desired = "request-token"
    params = %{"grant_type" => "refresh_token", "refresh_token" => desired, "client_id" => Ecto.UUID.generate()}
    conn = connection(%{"request" => jwt(params)}, "/oauth2/token?grant_type=authorization_code&code=unrelated-code")

    expect(Repo, :one, fn query ->
      {_, args} = Repo.to_sql(:all, query)
      assert desired in args
      refute "unrelated-code" in args
      Mimic.call_original(Repo, :one, [query])
    end)

    assert %{status: 200} = exchange(conn, fn %RefreshTokenRequest{refresh_token: ^desired} -> success() end)
  end

  test "body credentials override request-object claims for both parsing and locking" do
    claims = %{"grant_type" => "refresh_token", "refresh_token" => "claim-token", "client_id" => Ecto.UUID.generate()}
    conn = connection(%{"request" => jwt(claims), "refresh_token" => "body-token"})

    expect(Repo, :one, fn query ->
      {_, args} = Repo.to_sql(:all, query)
      assert "body-token" in args
      refute "claim-token" in args
      Mimic.call_original(Repo, :one, [query])
    end)

    assert %{status: 200} = exchange(conn, fn %RefreshTokenRequest{refresh_token: "body-token"} -> success() end)
  end

  for envelope <- [:query, :body],
      uri <- [
        "http://127.0.0.1/internal",
        "http://[::ffff:127.0.0.1]/internal",
        "https://request.example.test/object",
        "file:///private/object"
      ] do
    @tag envelope: envelope, uri: uri, external_uri: true
    test "#{envelope} external request URI #{uri} is rejected before network or database work", %{
      envelope: envelope,
      uri: uri
    } do
      reject(&Finch.request/2)
      reject(&Repo.transaction/1)

      conn =
        case envelope do
          :query -> connection(%{}, "/oauth2/token?" <> URI.encode_query(%{"request_uri" => uri}))
          :body -> connection(%{"request_uri" => uri})
        end

      assert %{status: 400} = exchange(conn, fn _ -> flunk("external request URI authorized") end)
      assert_receive {:response_transaction, false, %Error{error: :invalid_request, error_description: description}}
      assert description =~ "External request_uri is not supported"
    end
  end

  test "a query request object takes precedence over external URIs in either envelope" do
    reject(&Finch.request/2)
    claims = %{"grant_type" => "refresh_token", "refresh_token" => "inline-token", "client_id" => Ecto.UUID.generate()}
    query = URI.encode_query(%{"request" => jwt(claims), "request_uri" => "http://127.0.0.1/query"})
    conn = connection(%{"request_uri" => "http://127.0.0.1/body"}, "/oauth2/token?" <> query)
    assert %{status: 200} = exchange(conn, fn %RefreshTokenRequest{refresh_token: "inline-token"} -> success() end)
  end

  test "a body request object takes precedence over a body external URI" do
    reject(&Finch.request/2)
    claims = %{"grant_type" => "refresh_token", "refresh_token" => "inline-token", "client_id" => Ecto.UUID.generate()}
    conn = connection(%{"request" => jwt(claims), "request_uri" => "http://127.0.0.1/body"})
    assert %{status: 200} = exchange(conn, fn %RefreshTokenRequest{refresh_token: "inline-token"} -> success() end)
  end

  test "a query external URI is rejected rather than falling back to a body request object" do
    reject(&Finch.request/2)
    claims = %{"grant_type" => "refresh_token", "refresh_token" => "inline-token", "client_id" => Ecto.UUID.generate()}
    conn = connection(%{"request" => jwt(claims)}, "/oauth2/token?request_uri=http%3A%2F%2F127.0.0.1")
    assert %{status: 400} = exchange(conn, fn _ -> flunk("lower-priority request authorized") end)
    assert_receive {:response_transaction, false, %Error{error_description: description}}
    assert description =~ "External request_uri is not supported"
  end

  test "a malformed higher-priority request object never falls back to an external URI" do
    reject(&Finch.request/2)

    conn =
      connection(%{"request_uri" => "http://127.0.0.1/body"}, "/oauth2/token?request=&request_uri=http%3A%2F%2F127.0.0.1")

    assert %{status: 400} = exchange(conn, fn _ -> flunk("malformed request authorized") end)
    assert_receive {:response_transaction, false, %Error{error_description: "Unsigned request jwt param is malformed."}}
  end

  test "query stored-request URNs retain the upstream lookup without a network fetch" do
    reject(&Finch.request/2)

    stored =
      Repo.insert!(%Boruta.Ecto.AuthorizationRequest{
        client_id: Ecto.UUID.generate(),
        expires_at: System.system_time(:second) + 60
      })

    uri = "urn:ietf:params:oauth:request_uri:" <> stored.id

    conn =
      connection(
        %{"grant_type" => "refresh_token", "refresh_token" => "stored-request-token"},
        "/oauth2/token?" <> URI.encode_query(%{"request_uri" => uri})
      )

    assert %{status: 200} =
             exchange(conn, fn %RefreshTokenRequest{client_id: client_id, refresh_token: "stored-request-token"} ->
               assert client_id == stored.client_id
               success()
             end)
  end

  test "an invalid stored-request ID retains the upstream error without fetching a URI" do
    reject(&Finch.request/2)
    uri = "urn:ietf:params:oauth:request_uri:not-an-id"
    conn = connection(%{}, "/oauth2/token?" <> URI.encode_query(%{"request_uri" => uri}))
    assert %{status: 400} = exchange(conn, fn _ -> flunk("invalid stored request authorized") end)

    assert_receive {:response_transaction, false,
                    %Error{error_description: "Could not fetch stored authorization request."}}
  end

  for authentication <- [:claim_secret, :basic_with_claim_assertion] do
    @tag authentication: authentication
    test "request objects retain upstream client authentication for #{authentication}", %{authentication: authentication} do
      id = Ecto.UUID.generate()
      claims = %{"grant_type" => "refresh_token", "refresh_token" => "token", "client_id" => id}

      claims =
        case authentication do
          :claim_secret ->
            Map.put(claims, "client_secret", "claim-only-secret")

          :basic_with_claim_assertion ->
            Map.merge(claims, %{
              "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
              "client_assertion" => "invalid-claim-assertion"
            })
        end

      conn = connection(%{"request" => jwt(claims)})

      conn =
        if authentication == :basic_with_claim_assertion,
          do: Plug.Conn.put_req_header(conn, "authorization", "Basic " <> Base.encode64(id <> ":header-secret")),
          else: conn

      assert {:ok, expected} = Request.token_request(conn)

      assert %{status: 200} =
               exchange(conn, fn actual ->
                 assert actual == expected
                 success()
               end)
    end
  end

  test "a malformed request object has upstream invalid_request semantics without authorizing" do
    assert %{status: 400} =
             exchange(connection(%{"request" => "malformed"}), fn _ -> flunk("invalid request authorized") end)

    assert_receive {:response_transaction, false,
                    %Error{error: :invalid_request, error_description: "Unsigned request jwt param is malformed."}}
  end

  defp exchange(conn, authorize), do: Exchange.token(conn, Response, authorize: authorize)

  defp success do
    {:ok, %{token: %Token{type: "access_token", value: "issued", expires_at: System.system_time(:second) + 60}}}
  end

  defp connection(params \\ nil, path \\ "/oauth2/token") do
    params =
      params ||
        %{
          "grant_type" => "authorization_code",
          "code" => "missing",
          "client_id" => Ecto.UUID.generate(),
          "redirect_uri" => "https://example.test/callback"
        }

    :post |> Plug.Test.conn(path, params) |> Plug.Conn.fetch_query_params()
  end

  defp jwt(claims) do
    Enum.map_join([%{"alg" => "none"}, claims], ".", fn value ->
      value |> JSON.encode!() |> Base.url_encode64(padding: false)
    end) <> "."
  end
end
