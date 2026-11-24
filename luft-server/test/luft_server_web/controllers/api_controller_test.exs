defmodule LuftServerWeb.APIControllerTest do
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.FakeTuist
  alias LuftServer.NativeAuth

  defp login(conn) do
    provider = FakeTuist.stub()
    verifier = String.duplicate("x", 43)

    login =
      get(conn, "/oauth2/authorize", %{
        "client_id" => NativeAuth.client_id(),
        "response_type" => "code",
        "redirect_uri" => "luft://oauth-callback",
        "state" => "state",
        "code_challenge_method" => "S256",
        "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
      })

    {code, query} = FakeTuist.authorize(provider, redirected_to(login))

    callback =
      login |> recycle() |> get("/auth/callback", %{"code" => code, "state" => query["state"]})

    native =
      callback |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    credentials =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        "/oauth2/token",
        URI.encode_query(%{
          grant_type: "authorization_code",
          client_id: NativeAuth.client_id(),
          code: native["code"],
          code_verifier: verifier,
          redirect_uri: "luft://oauth-callback"
        })
      )
      |> json_response(200)

    {put_req_header(build_conn(), "authorization", "Bearer " <> credentials["access_token"]),
     credentials}
  end

  test "routed native login calls the API with server-held Tuist credentials", %{conn: conn} do
    {conn, _credentials} = login(conn)
    assert %{"organizations" => []} = conn |> get("/api/organizations") |> json_response(200)
    assert_received {:tuist_api, ["Bearer access-1"]}

    pid = self()

    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      assert upstream.host == "tuist.test"
      assert get_req_header(upstream, "authorization") == ["Bearer access-1"]
      send(pid, {upstream.method, upstream.request_path, upstream.query_string})
      Req.Test.json(upstream, %{projects: [%{name: "app"}], next_page: nil})
    end)

    assert %{"projects" => [%{"name" => "app"}]} =
             conn |> recycle() |> get("/api/projects?account=team&page=2") |> json_response(200)

    assert_received {"GET", "/api/projects", "account=team&page=2"}

    assert %{"error" => "not_found"} =
             conn |> recycle() |> get("/api/internal/secrets") |> json_response(404)

    assert %{"error" => "unauthenticated"} =
             conn
             |> recycle()
             |> put_req_header("authorization", "Bearer access-1")
             |> get("/api/projects")
             |> json_response(401)
  end

  test "writes retain their body and upstream errors without replaying", %{conn: conn} do
    {conn, credentials} = login(conn)
    pid = self()

    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      {:ok, body, upstream} = read_body(upstream)
      assert Jason.decode!(body) == %{"content" => "Hello", "request_id" => "deduplicate-me"}
      assert upstream.request_path == "/api/me/push-devices"
      send(pid, :write)
      upstream |> put_status(503) |> Req.Test.json(%{message: "Try later"})
    end)

    assert %{"message" => "Try later"} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/me/push-devices",
               Jason.encode!(%{content: "Hello", request_id: "deduplicate-me"})
             )
             |> json_response(503)

    assert_received :write
    refute_received :write

    assert build_conn()
           |> put_req_header("authorization", "Bearer " <> credentials["refresh_token"])
           |> post("/api/accounts/team/threads", %{})
           |> json_response(401)
  end

  test "runner credentials work only at the machine API and expire with the Luft session", %{
    conn: conn
  } do
    {conn, credentials} = login(conn)

    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      case upstream.request_path do
        "/oauth2/revoke" ->
          send_resp(upstream, 200, "")

        "/.well-known/openid-configuration" ->
          Req.Test.json(upstream, %{
            issuer: "https://tuist.test",
            revocation_endpoint: "https://tuist.test/oauth2/revoke"
          })
      end
    end)

    runner =
      conn
      |> post("/api/me/%74hread-runners", %{name: "Mac", platform: "macos"})
      |> json_response(201)

    refute runner["token"] =~ "tuist-machine-secret"
    assert String.starts_with?(runner["token"], "luft_runner_local_")
    machine = put_req_header(build_conn(), "authorization", "Bearer " <> runner["token"])

    assert %{"requests" => []} =
             machine |> post("/api/thread-runner/poll?wait_ms=1", %{}) |> json_response(200)

    assert machine |> recycle() |> get("/api/projects") |> json_response(401)
    assert conn |> recycle() |> post("/auth/logout", %{}) |> response(204)
    assert machine |> recycle() |> post("/api/thread-runner/poll", %{}) |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer " <> credentials["access_token"])
           |> get("/api/me")
           |> json_response(401)
  end

  test "preview media and installation links use Luft, while storage downloads stay intact", %{
    conn: conn
  } do
    {conn, _} = login(conn)

    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      case upstream.request_path do
        "/api/projects/team/app/previews" ->
          Req.Test.json(upstream, %{
            previews: [
              %{
                url: "https://tuist.test/team/app/previews/1",
                icon_url: "https://tuist.test/team/app/previews/1/icon.png",
                device_url:
                  "itms-services://?action=download-manifest&url=" <>
                    URI.encode_www_form(
                      "https://tuist.test/team/app/previews/1/manifest.plist?token=signed"
                    ),
                release_notes: "Visit https://tuist.test/docs",
                builds: [%{url: "https://storage.test/build.zip"}]
              }
            ]
          })

        "/team/app/previews/1/manifest.plist" ->
          assert upstream.query_string == "token=signed"

          upstream
          |> put_resp_content_type("application/xml")
          |> send_resp(
            200,
            "<url>https://tuist.test/team/app/previews/1/app.ipa?token=signed</url>"
          )
      end
    end)

    %{"previews" => [preview]} =
      conn |> get("/api/projects/team/app/previews") |> json_response(200)

    assert preview["icon_url"] == "https://luft.test/team/app/previews/1/icon.png"
    assert preview["release_notes"] == "Visit https://tuist.test/docs"
    assert preview["builds"] == [%{"url" => "https://storage.test/build.zip"}]
    assert preview["device_url"] =~ URI.encode_www_form("https://luft.test/")

    assert build_conn()
           |> get("/team/app/previews/1/manifest.plist?token=signed")
           |> response(200) =~ "https://luft.test/team/app/previews/1/app.ipa"
  end

  test "preview redirects never send clients back to Tuist and reject unsafe paths" do
    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      assert upstream.request_path == "/team/app/previews/1/app.ipa"

      upstream
      |> put_resp_header("location", "https://tuist.test/team/app/previews/1/download")
      |> send_resp(302, "")
    end)

    assert build_conn() |> get("/team/app/previews/1/app.ipa") |> redirected_to() ==
             "https://luft.test/team/app/previews/1/download"

    Req.Test.stub(LuftServer.Tuist, fn upstream ->
      upstream
      |> put_resp_header("location", "https://storage.test/app.ipa?signed=1")
      |> send_resp(302, "")
    end)

    assert build_conn() |> get("/team/app/previews/1/app.ipa") |> redirected_to() ==
             "https://storage.test/app.ipa?signed=1"

    Req.Test.stub(LuftServer.Tuist, fn _ -> flunk("unsafe preview paths must not reach Tuist") end)

    assert build_conn() |> get("/team/app/previews/%2E%2E/icon.png") |> json_response(404)
  end
end
