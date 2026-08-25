defmodule TuistWeb.Plugs.RunnersEnabledPlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Test

  alias Tuist.Environment
  alias TuistWeb.Plugs.RunnersEnabledPlug

  setup :set_mimic_from_context

  test "passes through when runners are enabled" do
    stub(Environment, :runners_enabled?, fn -> true end)
    conn = conn(:get, "/")

    assert RunnersEnabledPlug.call(conn, []) == conn
  end

  test "returns not found when runners are disabled" do
    stub(Environment, :runners_enabled?, fn -> false end)
    conn = conn(:get, "/")

    conn = RunnersEnabledPlug.call(conn, [])

    assert conn.status == 404
    assert conn.resp_body == ""
    assert conn.halted
  end
end
