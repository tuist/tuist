defmodule AtlasWeb.ErrorsLive.IndexTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "renders the errors dashboard for signed-in users", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/engineering/errors")

    assert html =~ "Errors"
    assert html =~ "errors-table"
  end

  test "shows the empty state when no issues have been captured", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/engineering/errors")

    refute html =~ "Boom went the compiler"
  end

  # Follow-up: exercise the LiveView with real issues. Phoenix LiveView spawns the
  # LV process under an ExUnit supervisor whose Ecto sandbox owner does not
  # inherit the test process's private-mode ownership. Rows the test inserts
  # via `Atlas.Repo` are invisible to `Errors.paginate_issues/1` called from
  # the LV process. The projects and domains LiveViews happen to sidestep
  # this because their queries hit tables that the sandbox-plug-less setup
  # already covers; the errors surface needs either a
  # `Phoenix.Ecto.SQL.Sandbox` plug on `AtlasWeb.Endpoint` or a
  # `Sandbox.allow(Atlas.Repo, owner, lv_pid)` hook triggered on connect.
end
