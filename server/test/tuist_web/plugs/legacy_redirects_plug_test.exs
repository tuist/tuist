defmodule TuistWeb.Plugs.LegacyRedirectsPlugTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Tuist.Environment
  alias TuistWeb.Plugs.LegacyRedirectsPlug

  @endpoint TuistWeb.Endpoint

  describe "call/2" do
    test "redirects legacy blog post to case study" do
      conn = %{build_conn() | request_path: "/blog/2024/12/16/trendyol"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/customers/trendyol"
      assert conn.halted
    end

    test "redirects docs locale paths to locale-first docs paths" do
      conn = %{build_conn() | request_path: "/docs/ja/guides/features/cache"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/ja/docs/guides/features/cache"
      assert conn.halted
    end

    test "preserves query strings when redirecting docs locale paths" do
      conn = %{build_conn() | request_path: "/docs/ja/guides/features/cache", query_string: "tab=setup"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/ja/docs/guides/features/cache?tab=setup"
      assert conn.halted
    end

    test "passes through non-matching paths" do
      conn = %{build_conn() | request_path: "/blog/2024/01/01/other-post"}

      conn = LegacyRedirectsPlug.call(conn, [])

      refute conn.halted
      assert conn.status != 301
    end

    test "redirects docs content paths through the VitePress redirect set" do
      conn = %{build_conn() | request_path: "/en/docs/guides/features/insights"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/docs/guides/features/build-insights"
      assert conn.halted
    end

    test "redirects legacy docs host paths to the current docs host" do
      conn = %{build_conn() | host: "docs.tuist.dev", request_path: "/en/guides/features/insights"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301

      assert redirected_to(conn, 301) ==
               Environment.app_url(path: "/en/docs/guides/features/build-insights")

      assert conn.halted
    end

    test "falls back unsupported legacy docs host locales to english" do
      conn = %{build_conn() | host: "docs.tuist.dev", request_path: "/pt/guides/features/cache"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == Environment.app_url(path: "/en/docs/guides/features/cache")
      assert conn.halted
    end

    test "normalizes legacy docs paths and resolves content redirects in one hop" do
      conn = %{build_conn() | request_path: "/docs/en/guides/develop/build/cache", query_string: "tab=setup"}

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/docs/guides/features/cache?tab=setup"
      assert conn.halted
    end

    test "redirects external documentation targets" do
      conn = %{
        build_conn()
        | request_path: "/en/docs/reference/project-description/structs/project",
          query_string: "tab=api"
      }

      conn = LegacyRedirectsPlug.call(conn, [])

      assert conn.status == 301

      assert redirected_to(conn, 301) ==
               "https://projectdescription.tuist.dev/documentation/projectdescription?tab=api"

      assert conn.halted
    end
  end
end
