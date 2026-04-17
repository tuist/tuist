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

    test "redirects docs locale paths to locale-first docs paths", %{conn: conn} do
      conn = %{conn | request_path: "/docs/ja/guides/features/cache"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/ja/docs/guides/features/cache"
      assert conn.halted
    end

    test "preserves query strings when redirecting docs locale paths", %{conn: conn} do
      conn = %{conn | request_path: "/docs/ja/guides/features/cache", query_string: "tab=setup"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/ja/docs/guides/features/cache?tab=setup"
      assert conn.halted
    end

    test "passes through non-matching paths", %{conn: conn} do
      conn = %{conn | request_path: "/blog/2024/01/01/other-post"}

      conn = LegacyRedirectsPlug.call(conn, [])

      refute conn.halted
      assert conn.status != 301
    end

    test "redirects docs content paths via Tuist.Docs.Redirects", %{conn: conn} do
      conn = %{conn | request_path: "/en/docs/cli/debugging"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/docs/references/cli/debugging"
      assert conn.halted
    end

    test "redirects docs content paths across locales", %{conn: conn} do
      conn = %{conn | request_path: "/ja/docs/cli/cache/warm"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/ja/docs/references/cli/cache/warm"
      assert conn.halted
    end

    test "normalizes and redirects content paths in a single hop", %{conn: conn} do
      conn = %{conn | request_path: "/docs/en/cli/debugging"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/docs/references/cli/debugging"
      assert conn.halted
    end

    test "preserves query strings when redirecting docs content paths", %{conn: conn} do
      conn = %{conn | request_path: "/en/docs/cli/debugging", query_string: "foo=bar"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/docs/references/cli/debugging?foo=bar"
      assert conn.halted
    end
  end
end
