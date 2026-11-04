defmodule AtlasWeb.SpecLive.FormTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the new spec form mounts without a persisted spec", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{role: :executive})
    assert {:ok, _view, html} = live(conn, ~p"/engineering/specs/new")
    assert html =~ "New spec"
  end
end
