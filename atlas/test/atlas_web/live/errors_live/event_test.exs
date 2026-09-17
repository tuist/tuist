defmodule AtlasWeb.ErrorsLive.EventTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "redirects to the errors dashboard when the issue does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/engineering/errors"}}} =
             live(
               conn,
               ~p"/engineering/errors/00000000-0000-0000-0000-000000000000/events/some-event"
             )
  end

  # TODO: exercise the "renders an event" happy path once the LV → sandbox
  # visibility issue described in `index_test.exs` is resolved.
end
