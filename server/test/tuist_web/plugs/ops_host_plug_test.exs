defmodule TuistWeb.Plugs.OpsHostPlugTest do
  use TuistTestSupport.Cases.ConnCase
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.OpsHostPlug

  setup :verify_on_exit!

  test "allows ops routes when no ops hosts are configured in self-hosted deployments", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> [] end)
    stub(Environment, :tuist_hosted?, fn -> false end)

    conn = %{conn | host: "tuist.dev"}

    assert OpsHostPlug.call(conn, []) == conn
  end

  test "raises not found when no ops hosts are configured in Tuist-hosted deployments", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> [] end)
    stub(Environment, :tuist_hosted?, fn -> true end)

    conn = %{conn | host: "tuist.dev"}

    assert_raise NotFoundError, "The page you are looking for doesn't exist or has been moved.", fn ->
      OpsHostPlug.call(conn, [])
    end
  end

  test "allows ops routes on a configured ops host", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "ops.tuist.dev"}

    assert OpsHostPlug.call(conn, []) == conn
  end

  test "raises not found for non-ops hosts when ops hosts are configured", %{conn: conn} do
    stub(Environment, :ops_hosts, fn -> ["ops.tuist.dev"] end)

    conn = %{conn | host: "tuist.dev"}

    assert_raise NotFoundError, "The page you are looking for doesn't exist or has been moved.", fn ->
      OpsHostPlug.call(conn, [])
    end
  end
end
