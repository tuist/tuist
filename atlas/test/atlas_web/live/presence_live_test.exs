defmodule AtlasWeb.PresenceLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Atlas.Presence
  alias Atlas.Presence.Connection
  alias Atlas.Repo

  @moduletag :presence_tracking

  setup :set_mimic_from_context

  test "live navigation removes the previous page lease without removing another tab", %{conn: conn} do
    test_pid = self()

    stub(Presence, :track, fn user, connection_id ->
      {:ok, tracker} = Mimic.call_original(Presence, :track, [user, connection_id])
      send(test_pid, {:tracking, connection_id, tracker})
      {:ok, tracker}
    end)

    {conn, user} = log_in_user(conn)
    other_tab = Ecto.UUID.generate()
    assert {:ok, _} = Presence.sync(user, other_tab, %{"resource" => "profile"})
    {:ok, view, _html} = live(conn, ~p"/people")
    assert_receive {:tracking, old_connection, old_tracker}
    old_ref = Process.monitor(old_tracker)

    {:ok, next_view, _html} =
      view
      |> element("a[href='/tasks']")
      |> render_click()
      |> follow_redirect(conn, ~p"/tasks")

    assert_receive {:tracking, next_connection, next_tracker}
    assert_receive {:DOWN, ^old_ref, :process, ^old_tracker, :normal}

    connections = Repo.all(from c in Connection, where: c.user_id == ^user.id)
    assert Enum.sort(Enum.map(connections, & &1.connection_id)) == Enum.sort([other_tab, next_connection])
    refute Enum.any?(connections, &(&1.connection_id == old_connection))
    assert Enum.find(connections, &(&1.connection_id == next_connection)).location == "tasks"

    next_ref = Process.monitor(next_tracker)
    GenServer.stop(next_view.pid, :normal)
    assert_receive {:DOWN, ^next_ref, :process, ^next_tracker, :normal}
    assert Repo.exists?(from c in Connection, where: c.user_id == ^user.id and c.connection_id == ^other_tab)
  end
end
