defmodule LuftServerWeb.AuthFlowTest do
  @moduledoc """
  Signing in with Tuist end to end against a stand-in provider: the
  authorization request, the callback's state, PKCE and ID token checks, the
  session cookie, the organizations API, refresh and sign-out.
  """
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.FakeTuist

  @web "https://luft.test"

  defp sign_in(conn, provider, login_params \\ %{}) do
    login =
      get(conn, "/auth/login", Map.merge(%{"return_to" => "/threads?tab=all"}, login_params))

    {code, query} = FakeTuist.authorize(provider, redirected_to(login))

    callback =
      login
      |> recycle()
      |> get("/auth/callback", %{"code" => code, "state" => query["state"]})

    {callback, query}
  end

  defp api(conn, method, path, body \\ nil) do
    conn = conn |> recycle() |> put_req_header("origin", @web)

    case method do
      :get ->
        get(conn, path)

      :post ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(body))
    end
  end

  test "signs in and lists and creates the person's Tuist organizations", %{conn: conn} do
    provider = FakeTuist.stub(organizations: [%{"id" => 1, "name" => "tuist", "plan" => "pro"}])
    {callback, query} = sign_in(conn, provider)

    assert query["scope"] ==
             "openid profile email account:organizations:write luft:app mcp account:delete account:members:read account:sandboxes:write account:repositories:read account:repositories:write project:admin:read project:previews:read project:previews:write"

    assert query["code_challenge_method"] == "S256"
    assert query["redirect_uri"] == @web <> "/auth/callback"
    refute Map.has_key?(query, "prompt")

    assert redirected_to(callback) == "/threads?tab=all"
    # RFC 10017 6.1.3.2: no other host or script can set or read it.
    assert %{http_only: true, secure: true, same_site: "Strict", path: "/"} =
             cookie = callback.resp_cookies["__Host-Http-luft_session"]

    refute Map.has_key?(cookie, :domain)
    refute callback.resp_body =~ "access-1", "Tuist's tokens must never reach the browser"

    assert %{"id" => "42", "handle" => "person", "email" => "person@example.com"} =
             callback |> api(:get, "/api/me") |> json_response(200)

    assert %{"organizations" => [%{"name" => "tuist", "plan" => "pro"}]} =
             callback |> api(:get, "/api/organizations") |> json_response(200)

    assert_received {:tuist_api, ["Bearer access-1"]}

    assert %{"name" => "new-org"} =
             callback
             |> api(:post, "/api/organizations", %{name: "new-org"})
             |> json_response(201)

    assert %{"organizations" => [_, %{"name" => "new-org"}]} =
             callback |> api(:get, "/api/organizations") |> json_response(200)

    logout = api(callback, :post, "/auth/logout", %{})
    assert logout.status == 204
    assert logout |> api(:get, "/api/me") |> json_response(401)
  end

  test "signup asks Tuist to show registration", %{conn: conn} do
    provider = FakeTuist.stub()
    {_callback, query} = sign_in(conn, provider, %{"signup" => "1"})
    assert query["prompt"] == "create"
  end

  test "refuses a callback whose state did not start in this browser", %{conn: conn} do
    provider = FakeTuist.stub()
    login = get(conn, "/auth/login")
    {code, _query} = FakeTuist.authorize(provider, redirected_to(login))

    assert login
           |> recycle()
           |> get("/auth/callback", %{"code" => code, "state" => "forged"})
           |> json_response(400)

    # Nor in another browser with no sign-in in flight.
    assert build_conn()
           |> get("/auth/callback", %{"code" => code, "state" => "x"})
           |> json_response(400)
  end

  test "refuses an ID token minted for another sign-in", %{conn: conn} do
    provider = FakeTuist.stub(nonce: "someone-elses-nonce")
    {callback, _query} = sign_in(conn, provider)
    assert json_response(callback, 502)
    refute Map.has_key?(callback.resp_cookies, "__Host-Http-luft_session")
  end

  test "refuses an ID token from another issuer or for another client", %{conn: conn} do
    for claims <- [%{"iss" => "https://evil.test"}, %{"aud" => "another-client"}] do
      provider = FakeTuist.stub(claims: claims)
      {callback, _query} = sign_in(conn, provider)
      assert json_response(callback, 502)
    end
  end

  test "never returns anywhere but the Luft web app", %{conn: conn} do
    for return_to <- ["https://evil.test/steal", "//evil.test", "/\\evil.test", "/\t/evil.test"] do
      provider = FakeTuist.stub()
      {callback, _query} = sign_in(conn, provider, %{"return_to" => return_to})
      assert redirected_to(callback) == "/", "#{inspect(return_to)} must not be followed"
    end
  end

  test "refreshes an expiring access token once and signs out when Tuist refuses", %{conn: conn} do
    provider = FakeTuist.stub(expires_in: 0)
    {callback, _query} = sign_in(conn, provider)

    assert callback |> api(:get, "/api/organizations") |> json_response(200)
    assert_received {:tuist_api, ["Bearer access-refreshed"]}
    # The refreshed token is fresh, so the next call doesn't refresh again.
    assert callback |> api(:get, "/api/organizations") |> json_response(200)
    assert Agent.get(provider.state, & &1.refreshes) == 1

    # Tuist refuses the grant, or answers without a token once the user is deleted.
    for refresh <- [:invalid_grant, :user_deleted] do
      refused = FakeTuist.stub(expires_in: 0, refresh: refresh)
      {callback, _query} = sign_in(build_conn(), refused)

      assert %{"login_url" => _} =
               callback |> api(:get, "/api/organizations") |> json_response(401)

      assert callback |> api(:get, "/api/me") |> json_response(401)
    end
  end

  test "keeps the session when Tuist refuses the client rather than the grant", %{conn: conn} do
    # A client secret mid-rotation: the person's grant is still good.
    provider = FakeTuist.stub(expires_in: 0, refresh: :invalid_client)
    {callback, _query} = sign_in(conn, provider)

    assert %{"error" => "tuist_unavailable"} =
             callback |> api(:get, "/api/organizations") |> json_response(502)

    assert callback |> api(:get, "/api/me") |> json_response(200)
  end

  test "refuses writes from other origins, sibling subdomains included", %{conn: conn} do
    provider = FakeTuist.stub()
    {callback, _query} = sign_in(conn, provider)

    forged =
      callback
      |> recycle()
      |> put_req_header("origin", "https://evil.luft.test")
      |> put_req_header("content-type", "application/json")
      |> post("/api/organizations", JSON.encode!(%{name: "x"}))

    assert json_response(forged, 403)
  end
end
