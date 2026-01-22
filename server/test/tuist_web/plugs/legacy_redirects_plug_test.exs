defmodule TuistWeb.Plugs.LegacyRedirectsPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Plugs.LegacyRedirectsPlug

  describe "call/2" do
    test "redirects legacy blog post to case study", %{conn: conn} do
      conn = %{conn | request_path: "/blog/2024/12/16/trendyol"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/customers/trendyol"
      assert conn.halted
    end

    test "passes through non-matching paths", %{conn: conn} do
      conn = %{conn | request_path: "/blog/2024/01/01/other-post"}

      conn = LegacyRedirectsPlug.call(conn, [])

      refute conn.halted
      assert conn.status != 301
    end
  end
end
