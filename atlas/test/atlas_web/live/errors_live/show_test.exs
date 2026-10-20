defmodule AtlasWeb.ErrorsLive.ShowTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "redirects to the errors dashboard when the issue does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/engineering/errors"}}} =
             live(conn, ~p"/engineering/errors/00000000-0000-0000-0000-000000000000")
  end

  test "redirects when the id is not a UUID", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/engineering/errors"}}} =
             live(conn, ~p"/engineering/errors/not-an-id")
  end

  # Follow-up: exercise the "renders an issue" happy path once the LV → sandbox
  # visibility issue described in `index_test.exs` is resolved. Inserting an
  # `Errors.Issue` in the test process is not visible to `Errors.fetch_issue/1`
  # from within the mounted LiveView process.
end
