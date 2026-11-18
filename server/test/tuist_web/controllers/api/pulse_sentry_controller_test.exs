defmodule TuistWeb.API.PulseSentryControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @envelope ~s({"event_id":"9ec79c33ec9942ab8353589fcb2e04dc"}\n{"type":"event"}\n{"message":"boom"}\n)

  setup do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    account = organization.account
    stub(Pulse, :available?, fn %{id: id} -> id == account.id end)

    stub(Environment, :sentry_pulse_dsn, fn ->
      "http://sentry:writer-secret@pulse.observability.svc.cluster.local:4000/v1/sentry/server/1"
    end)

    %{account: account}
  end

  defp token(account, scopes) do
    {:ok, {_record, token}} =
      Accounts.create_account_token(%{
        account: account,
        name: "pulse-#{System.unique_integer([:positive])}",
        scopes: scopes
      })

    token
  end

  defp post_envelope(conn, handle, auth, path \\ "atlas/api/1/envelope/") do
    conn
    |> put_req_header("content-type", "application/x-sentry-envelope")
    |> put_req_header("content-encoding", "identity")
    |> then(fn conn -> if auth, do: put_req_header(conn, "x-sentry-auth", auth), else: conn end)
    |> post("/api/accounts/#{handle}/pulse/sentry/#{path}", @envelope)
  end

  test "forwards a Sentry SDK's envelope to Pulse as the server's writer", %{conn: conn, account: account} do
    token = token(account, ["account:pulse:write"])

    expect(Req, :request, fn request ->
      assert request.method == :post

      assert URI.to_string(request.url) ==
               "http://pulse.observability.svc.cluster.local:4000/v1/sentry/atlas/api/1/envelope/"

      assert request.body == @envelope

      assert request.headers["x-sentry-auth"] == [
               "Sentry sentry_version=7, sentry_key=sentry, sentry_secret=writer-secret"
             ]

      assert request.headers["content-encoding"] == ["identity"]
      refute Map.has_key?(request.headers, "authorization")
      {:ok, %Req.Response{status: 200, body: ~s({"id":"9ec79c33ec9942ab8353589fcb2e04dc"})}}
    end)

    # The DSN's userinfo percent-encodes the token's base64 `/`, `+` and `=`.
    key = URI.encode(token, &URI.char_unreserved?/1)
    assert key =~ "%3D"

    conn =
      post_envelope(
        conn,
        account.name,
        "Sentry sentry_version=7, sentry_client=sentry.elixir/13.1.0, sentry_key=#{key}"
      )

    assert json_response(conn, 200) == %{"id" => "9ec79c33ec9942ab8353589fcb2e04dc"}
  end

  test "rejects tokens without the scope, of another account, or of an account not enrolled in Pulse",
       %{conn: conn, account: account} do
    reject(&Req.request/1)
    other = AccountsFixtures.organization_fixture(preload: [:account]).account

    assert conn
           |> post_envelope(account.name, "Sentry sentry_key=#{token(account, ["account:cache:read"])}")
           |> json_response(403)

    assert conn
           |> post_envelope(account.name, "Sentry sentry_key=#{token(other, ["account:pulse:write"])}")
           |> json_response(403)

    assert conn
           |> post_envelope(other.name, "Sentry sentry_key=#{token(other, ["account:pulse:write"])}")
           |> json_response(403)

    assert conn |> post_envelope(account.name, nil) |> json_response(401)
    assert conn |> post_envelope(account.name, "Sentry sentry_key=tuist_not-a-token") |> json_response(401)
  end

  test "rejects a service Pulse would not accept before forwarding", %{conn: conn, account: account} do
    reject(&Req.request/1)
    auth = "Sentry sentry_key=#{token(account, ["account:pulse:write"])}"

    assert conn |> post_envelope(account.name, auth, "at%2Flas/api/1/envelope/") |> json_response(400)
    assert conn |> post_envelope(account.name, auth, "atlas/api/one/envelope/") |> json_response(400)
  end

  test "reports the server's own Pulse failures as unavailable, not as the caller's", %{conn: conn, account: account} do
    auth = "Sentry sentry_key=#{token(account, ["account:pulse:write"])}"

    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 401, body: "unauthorized"}} end)
    assert conn |> post_envelope(account.name, auth) |> json_response(502)

    expect(Req, :request, fn _ -> {:error, %Req.TransportError{reason: :econnrefused}} end)
    assert conn |> post_envelope(account.name, auth) |> json_response(503)
  end
end
