defmodule AtlasWeb.PeopleLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Presence

  test "directory receives pushed availability and page presence without navigation-history details", %{conn: conn} do
    {conn, _viewer} = log_in_user(conn)
    {_, teammate} = log_in_user(build_conn(), %{name: "Presence colleague"})
    {:ok, view, _} = live(conn, ~p"/people")
    selector = "#presence_people-#{teammate.id}"
    assert has_element?(view, "#{selector} [data-online='false']", "Offline")
    assert {:ok, _} = Presence.sync(teammate, Ecto.UUID.generate(), %{"resource" => "people"})
    # PostgreSQL notifications commit after transactions; the test notifier
    # carries the same invalidation over the local Oban transport.
    send(view.pid, :presence_changed)
    assert has_element?(view, "#{selector} [data-online='true']", "Online")
    assert has_element?(view, "[data-part='also-here']", "Presence colleague")
    render_hook(view, "presence_visibility", %{"visible" => false})
    assert has_element?(view, "#people-directory")
  end
end
