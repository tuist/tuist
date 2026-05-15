defmodule TuistWeb.Plugs.OpsRootRedirectPlugTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.Plugs.OpsRootRedirectPlug

  setup :verify_on_exit!

  test "redirects the configured ops host root to /ops", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "ops.tuist.dev", request_path: "/"}

    conn = OpsRootRedirectPlug.call(conn, [])

    assert redirected_to(conn, 302) == "/ops"
    assert conn.halted
  end

  test "preserves query params when redirecting", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "ops.tuist.dev", request_path: "/", query_string: "foo=bar"}

    conn = OpsRootRedirectPlug.call(conn, [])

    assert redirected_to(conn, 302) == "/ops?foo=bar"
    assert conn.halted
  end

  test "does not redirect non-ops hosts", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "tuist.dev", request_path: "/"}

    assert OpsRootRedirectPlug.call(conn, []) == conn
  end

  test "does not redirect non-root paths", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "ops.tuist.dev", request_path: "/projects"}

    assert OpsRootRedirectPlug.call(conn, []) == conn
  end
end
