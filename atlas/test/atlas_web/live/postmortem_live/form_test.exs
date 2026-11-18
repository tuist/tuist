defmodule AtlasWeb.PostmortemLive.FormTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the new postmortem form mounts without a persisted postmortem", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{role: :executive})
    assert {:ok, _view, _html} = live(conn, ~p"/engineering/postmortems/new")
  end
end
