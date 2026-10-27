defmodule TuistWeb.Oauth.AndroidCallbackControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  describe "GET /oauth/callback/android" do
    test "returns HTML page with custom scheme redirect", %{conn: conn} do
      conn = get(conn, "/oauth/callback/android", %{"code" => "test_code", "state" => "test_state"})

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]

      body = conn.resp_body
      assert body =~ "tuist://oauth-callback?"
      assert body =~ "code=test_code"
      assert body =~ "state=test_state"
      assert body =~ "Authentication complete"
      assert body =~ "intent://oauth-callback?"
      assert body =~ "scheme=tuist"
      assert body =~ "package=dev.tuist.app"
    end

    test "forwards error params to the app", %{conn: conn} do
      conn =
        get(conn, "/oauth/callback/android", %{
          "error" => "access_denied",
          "error_description" => "User denied"
        })

      assert conn.status == 200

      body = conn.resp_body
      assert body =~ "error=access_denied"
      assert body =~ "error_description=User+denied"
    end

    test "ignores unexpected params", %{conn: conn} do
      conn =
        get(conn, "/oauth/callback/android", %{
          "code" => "test_code",
          "state" => "test_state",
          "unexpected" => "should_be_ignored"
        })

      assert conn.status == 200

      body = conn.resp_body
      assert body =~ "code=test_code"
      refute body =~ "unexpected"
    end

    test "HTML-escapes params to prevent XSS", %{conn: conn} do
      conn =
        get(conn, "/oauth/callback/android", %{
          "code" => "<script>alert(1)</script>",
          "state" => "safe"
        })

      assert conn.status == 200

      body = conn.resp_body
      refute body =~ "<script>alert(1)</script>"
    end
  end
end
