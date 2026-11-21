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

      refute Map.has_key?(request.headers, "content-encoding")
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

  test "account producers retain multi-signal Sentry support", %{conn: conn, account: account} do
    body = @envelope <> ~s({"type":"log"}\n{"items":[]}\n{"type":"span"}\n{"name":"operation"}\n)

    expect(Req, :request, fn request ->
      assert request.body == body
      {:ok, %Req.Response{status: 200, body: "{}"}}
    end)

    assert conn |> post_encoded(account, "identity", body) |> json_response(200) == %{}
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

  defp post_encoded(conn, account, encoding, body) do
    conn
    |> put_req_header("content-type", "application/x-sentry-envelope")
    |> put_req_header("content-encoding", encoding)
    |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{token(account, ["account:pulse:write"])}")
    |> post("/api/accounts/#{account.name}/pulse/sentry/atlas/api/1/envelope/", body)
  end

  test "inflates gzip envelopes before forwarding, holding their inflated size to 1 MiB",
       %{conn: conn, account: account} do
    gzipped = :zlib.gzip(@envelope)

    expect(Req, :request, fn request ->
      assert request.body == @envelope
      refute Map.has_key?(request.headers, "content-encoding")
      {:ok, %Req.Response{status: 200, body: ~s({"id":"9ec79c33ec9942ab8353589fcb2e04dc"})}}
    end)

    assert conn |> post_encoded(account, "gzip", gzipped) |> json_response(200)

    # None of these reach Pulse: the single expectation above fails any
    # further request. A few KiB of gzip inflate past the limit; a body
    # missing its gzip trailer is incomplete, not an envelope to forward
    # cut short; and the server reads deflate as raw DEFLATE, which is not
    # what the encoding means to Sentry SDKs, so it is refused.
    bomb = :zlib.gzip(:binary.copy("a", 1_048_577))
    assert byte_size(bomb) < 4096
    assert conn |> post_encoded(account, "gzip", bomb) |> json_response(413)

    truncated = binary_part(gzipped, 0, byte_size(gzipped) - 4)

    assert conn |> post_encoded(account, "gzip", truncated) |> json_response(400) == %{
             "message" => "The envelope could not be decompressed."
           }

    assert conn |> post_encoded(account, "deflate", :zlib.compress(@envelope)) |> json_response(400) == %{
             "message" => "The envelope must be uncompressed, or gzip-, br- or zstd-encoded."
           }
  end

  test "forwards brotli and zstd envelopes encoded, for Pulse to decode and limit",
       %{conn: conn, account: account} do
    # Stands in for a brotli body; the server does not decode it.
    encoded = :crypto.strong_rand_bytes(64)

    expect(Req, :request, 2, fn request ->
      assert request.body == encoded
      assert request.headers["content-encoding"] in [["br"], ["zstd"]]
      {:ok, %Req.Response{status: 200, body: ~s({"id":"9ec79c33ec9942ab8353589fcb2e04dc"})}}
    end)

    assert conn |> post_encoded(account, "br", encoded) |> json_response(200)
    assert conn |> post_encoded(account, "zstd", encoded) |> json_response(200)

    # Pulse's own limit on the decoded envelope reads like the server's.
    expect(Req, :request, fn _ ->
      {:ok, %Req.Response{status: 413, body: "Failed to buffer the request body: length limit exceeded"}}
    end)

    assert conn |> post_encoded(account, "br", encoded) |> json_response(413) == %{
             "message" => "The envelope is larger than 1 MiB."
           }

    # Pulse's JSON rejections pass through; its HTTP layer's plain-text ones,
    # such as for a corrupt stream, are replaced by a JSON error.
    expect(Req, :request, 2, fn request ->
      if request.headers["content-encoding"] == ["br"],
        do: {:ok, %Req.Response{status: 400, body: "Failed to buffer the request body"}},
        else: {:ok, %Req.Response{status: 400, body: ~s({"error":"invalid envelope"})}}
    end)

    assert conn |> post_encoded(account, "br", encoded) |> json_response(400) == %{
             "message" => "The envelope could not be read."
           }

    assert conn |> post_encoded(account, "zstd", encoded) |> json_response(400) == %{"error" => "invalid envelope"}
  end

  test "preserves only Pulse rate-limit headers, including on successful mixed envelopes", %{conn: conn, account: account} do
    body = @envelope <> ~s({"type":"session"}\n{"sid":"synthetic-session","attrs":{"release":"test@1"}}\n)

    for status <- [200, 400, 413, 429] do
      expect(Req, :request, fn request ->
        assert request.body == body

        {:ok,
         %Req.Response{
           status: status,
           body: "{}",
           headers: %{
             "retry-after" => ["37"],
             "x-sentry-rate-limits" => ["37:error:organization", "19:session:organization"],
             "set-cookie" => ["not-forwarded=true"]
           }
         }}
      end)

      response = post_encoded(conn, account, "identity", body)
      assert response.status == status
      assert get_resp_header(response, "retry-after") == ["37"]
      assert get_resp_header(response, "x-sentry-rate-limits") == ["37:error:organization, 19:session:organization"]
      assert get_resp_header(response, "set-cookie") == []
    end
  end

  test "reports the server's own Pulse failures as unavailable, not as the caller's", %{conn: conn, account: account} do
    auth = "Sentry sentry_key=#{token(account, ["account:pulse:write"])}"

    expect(Req, :request, fn _ -> {:ok, %Req.Response{status: 401, body: "unauthorized"}} end)
    assert conn |> post_envelope(account.name, auth) |> json_response(502)

    expect(Req, :request, fn _ -> {:error, %Req.TransportError{reason: :econnrefused}} end)
    assert conn |> post_envelope(account.name, auth) |> json_response(503)
  end
end
