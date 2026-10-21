defmodule Tuist.OAuth.ExchangeTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.OAuth.Exchange
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defmodule OAuth do
    @moduledoc false
    def token(conn, application), do: conn.private.exchange.(conn, application)
  end

  defmodule Response do
    @moduledoc false
    def token_success(conn, _response) do
      send(self(), {:response_transaction, Repo.in_transaction?()})
      Plug.Conn.send_resp(conn, 200, "ok")
    end

    def token_error(conn, error) do
      send(self(), {:response_transaction, Repo.in_transaction?()})
      Plug.Conn.send_resp(conn, error.status, "error")
    end
  end

  test "exchange callbacks run inside a transaction but HTTP succeeds only after commit" do
    conn =
      connection(fn conn, application ->
        send(self(), {:exchange_transaction, Repo.in_transaction?()})
        application.token_success(conn, %Boruta.Oauth.TokenResponse{expires_in: 60})
      end)

    assert %{status: 200, state: :sent} = Exchange.token(conn, OAuth, Response)
    assert_receive {:exchange_transaction, true}
    assert_receive {:response_transaction, false}
  end

  test "a database lock timeout returns unavailable without invoking the grant or sending within a transaction" do
    expect(Repo, :query!, fn "SET LOCAL lock_timeout = '5s'" ->
      raise %Postgrex.Error{
        postgres: %{code: :lock_not_available, pg_code: "55P03", severity: "ERROR", message: "lock timeout"}
      }
    end)

    conn = connection(fn _, _ -> flunk("grant ran without acquiring the credential lock") end)
    assert %{status: 503, state: :sent} = Exchange.token(conn, OAuth, Response)
    assert_receive {:response_transaction, false}
  end

  test "a failed rotation rolls back replacement writes before sending an error" do
    conn =
      connection(fn conn, application ->
        user = AccountsFixtures.user_fixture()
        send(self(), {:new_user, user.id})

        application.token_error(conn, %Boruta.Oauth.Error{
          error: :unknown_error,
          status: :internal_server_error,
          error_description: "unavailable"
        })
      end)

    assert %{status: 500} = Exchange.token(conn, OAuth, Response)
    assert_receive {:new_user, id}
    assert Repo.get(Tuist.Accounts.User, id) == nil
    assert_receive {:response_transaction, false}
  end

  defp connection(fun) do
    :post
    |> Plug.Test.conn("/oauth2/token", %{"grant_type" => "authorization_code", "code" => "missing"})
    |> Plug.Conn.put_private(:exchange, fun)
    |> Map.put(:params, %{"grant_type" => "authorization_code", "code" => "missing"})
  end
end
