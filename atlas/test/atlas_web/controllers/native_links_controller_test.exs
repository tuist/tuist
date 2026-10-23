defmodule AtlasWeb.NativeLinksControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Demo
  alias AtlasWeb.NativeLinks.Config

  @id "0198f0a1-7c2e-7b3d-9f4a-1b2c3d4e5f60"
  @fingerprint Enum.map_join(1..32, ":", fn _ -> "AB" end)

  setup :verify_on_exit!

  describe "GET /.well-known/apple-app-site-association" do
    test "is not served until an app identity is configured", %{conn: conn} do
      stub(Config, :apple_app_ids, fn -> [] end)

      conn = get(conn, "/.well-known/apple-app-site-association")

      assert response(conn, 404)
    end

    test "claims only the allowlisted paths for the configured app IDs", %{conn: conn} do
      stub(Config, :apple_app_ids, fn -> ["U6LC622NKF.dev.tuist.atlas"] end)

      conn = get(conn, "/.well-known/apple-app-site-association")

      assert response_content_type(conn, :json) =~ "application/json"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
      assert get_resp_header(conn, "set-cookie") == []

      assert %{
               "applinks" => %{"details" => [%{"appIDs" => ["U6LC622NKF.dev.tuist.atlas"], "components" => components}]}
             } =
               json_response(conn, 200)

      paths = Enum.map(components, & &1["/"])
      assert "/tasks" in paths
      assert "/commercial/sales/accounts/????????-????-????-????-????????????" in paths
      assert "/open/invoices/????????-????-????-????-????????????" in paths
      refute "/commercial/finance" in paths
      refute Enum.any?(paths, &String.contains?(&1, "*"))
      assert Enum.all?(components, &(Map.keys(&1) == ["/"]))
    end

    test "does not negotiate on the Accept header", %{conn: conn} do
      stub(Config, :apple_app_ids, fn -> ["U6LC622NKF.dev.tuist.atlas"] end)

      conn = conn |> put_req_header("accept", "text/html") |> get("/.well-known/apple-app-site-association")

      assert json_response(conn, 200)
    end
  end

  describe "GET /.well-known/assetlinks.json" do
    test "is not served until a release-signing fingerprint is configured", %{conn: conn} do
      stub(Config, :android_sha256_fingerprints, fn -> [] end)

      assert conn |> get("/.well-known/assetlinks.json") |> response(404)
    end

    test "delegates link handling to the Atlas package", %{conn: conn} do
      stub(Config, :android_sha256_fingerprints, fn -> [@fingerprint] end)

      conn = conn |> put_req_header("accept", "*/*") |> get("/.well-known/assetlinks.json")

      assert [
               %{
                 "relation" => ["delegate_permission/common.handle_all_urls"],
                 "target" => %{
                   "namespace" => "android_app",
                   "package_name" => "dev.tuist.atlas",
                   "sha256_cert_fingerprints" => [@fingerprint]
                 }
               }
             ] = json_response(conn, 200)
    end
  end

  describe "GET /open/*" do
    setup do
      stub(Config, :origin, fn -> "https://atlas.example.org" end)
      :ok
    end

    test "offers the app and a sign-in protected browser fallback for records", %{conn: conn} do
      conn = get(conn, "/open/accounts/#{@id}")
      html = html_response(conn, 200)

      assert html =~ "Open this account"
      assert html =~ ~s(href="dev.tuist.atlas://navigate/accounts/#{@id}?server=https%3A%2F%2Fatlas.example.org")
      assert html =~ ~s(href="/commercial/sales/accounts/#{@id}")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "falls back to the list for records without a web detail page", %{conn: conn} do
      html = conn |> get("/open/tasks/#{@id}") |> html_response(200)

      assert html =~ ~s(href="dev.tuist.atlas://navigate/tasks/#{@id}?server=)
      assert html =~ ~s(href="/tasks")

      html = conn |> get("/open/invoices/#{@id}") |> html_response(200)
      assert html =~ ~s(href="/commercial/finance")
    end

    test "serves every native screen", %{conn: conn} do
      for {screen, fallback} <- [
            {"tasks", "/tasks"},
            {"accounts", "/commercial/sales/accounts"},
            {"invoices", "/commercial/finance"},
            {"time-off", "/people/time-off"},
            {"people", "/people"},
            {"profile", "/settings"}
          ] do
        html = conn |> get("/open/#{screen}") |> html_response(200)
        assert html =~ ~s(href="dev.tuist.atlas://navigate/#{screen}?server=)
        assert html =~ ~s(href="#{fallback}")
      end
    end

    test "uses the configured origin, never request host headers", %{conn: conn} do
      html =
        conn
        |> Map.put(:host, "attacker.example")
        |> put_req_header("x-forwarded-host", "attacker.example")
        |> get("/open/people")
        |> html_response(200)

      assert html =~ "server=https%3A%2F%2Fatlas.example.org"
      refute html =~ "attacker"
    end

    test "omits the app action without an HTTPS origin", %{conn: conn} do
      stub(Config, :origin, fn -> nil end)

      html = conn |> get("/open/tasks") |> html_response(200)

      refute html =~ "dev.tuist.atlas://"
      assert html =~ ~s(href="/tasks")
    end

    test "ignores query arguments instead of treating them as path segments", %{conn: conn} do
      html = conn |> get("/open/tasks?id=#{@id}") |> html_response(200)
      assert html =~ "Open Tasks"
      assert html =~ ~s(href="dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.example.org")
      refute html =~ @id

      html = conn |> get("/open/tasks?id[]=x&id[]=#{@id}") |> html_response(200)
      assert html =~ ~s(href="dev.tuist.atlas://navigate/tasks?server=)
      refute html =~ @id

      html = conn |> get("/open/people?screen=accounts&id=#{@id}") |> html_response(200)
      assert html =~ ~s(href="dev.tuist.atlas://navigate/people?server=)
      refute html =~ "accounts"

      html = conn |> get("/open/accounts/#{@id}?screen=tasks&id=other") |> html_response(200)
      assert html =~ ~s(href="dev.tuist.atlas://navigate/accounts/#{@id}?server=)
      assert html =~ ~s(href="/commercial/sales/accounts/#{@id}")
    end

    test "never forwards credential-bearing query arguments", %{conn: conn} do
      html =
        conn
        |> get("/open/tasks/#{@id}?token=secret-token&access_token=secret-access&server=https://evil.example")
        |> html_response(200)

      refute html =~ "secret-token"
      refute html =~ "secret-access"
      refute html =~ "evil.example"
      assert html =~ ~s(href="dev.tuist.atlas://navigate/tasks/#{@id}?server=https%3A%2F%2Fatlas.example.org")
      assert html =~ ~s(href="/tasks")
    end

    test "returns 404 for anything outside the allowlist", %{conn: conn} do
      for path <- [
            "/open/browser",
            "/open/notes",
            "/open/Tasks",
            "/open/people/#{@id}",
            "/open/profile/#{@id}",
            "/open/tasks/#{String.upcase(@id)}",
            "/open/tasks/not-a-uuid",
            "/open/tasks%2F#{@id}",
            "/open/tasks/#{@id}/edit",
            "/open"
          ] do
        assert conn |> get(path) |> response(404), "served #{path}"
      end
    end
  end

  test "the read-only demo serves none of the native link endpoints", %{conn: conn} do
    stub(Demo, :enabled?, fn -> true end)
    stub(Config, :apple_app_ids, fn -> ["U6LC622NKF.dev.tuist.atlas"] end)

    for path <- ["/.well-known/apple-app-site-association", "/.well-known/assetlinks.json", "/open/tasks"] do
      assert conn |> get(path) |> response(403), "served #{path}"
    end
  end
end
