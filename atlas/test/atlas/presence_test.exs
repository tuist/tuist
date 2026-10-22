defmodule Atlas.PresenceTest do
  use AtlasWeb.ConnCase, async: true

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Presence
  alias Atlas.Presence.Connection
  alias Atlas.Repo

  @moduletag :presence_tracking

  test "availability aggregates devices, hides locations, and expires abandoned connections", %{conn: conn} do
    {_, viewer} = log_in_user(conn)
    {_, teammate} = log_in_user(conn)
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()
    assert {:ok, _} = Presence.sync(teammate, first, %{"resource" => "tasks"})
    assert {:ok, _} = Presence.sync(teammate, second, %{"resource" => "people"})
    person = Enum.find(Presence.snapshot(viewer, "tasks").people, &(&1.id == teammate.id))
    assert person.online and person.here
    assert Map.keys(person) |> Enum.sort() == [:email, :here, :id, :name, :online]
    refute Enum.find(Presence.snapshot(viewer).people, &(&1.id == teammate.id)).here

    assert :ok = Presence.leave(viewer, first)
    assert Enum.find(Presence.snapshot(viewer).people, &(&1.id == teammate.id)).online
    assert :ok = Presence.leave(teammate, first)
    person = Enum.find(Presence.snapshot(viewer, "tasks").people, &(&1.id == teammate.id))
    assert person.online
    refute person.here

    Repo.update_all(from(c in Connection, where: c.user_id == ^teammate.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    refute Enum.find(Presence.snapshot(viewer).people, &(&1.id == teammate.id)).online
    assert :ok = Presence.prune()
    refute Repo.exists?(from c in Connection, where: c.user_id == ^teammate.id)

    assert :ok = Presence.renew(teammate, second, %{"resource" => "people"})
    assert Enum.find(Presence.snapshot(viewer, "people").people, &(&1.id == teammate.id)).here
    refute Enum.find(Presence.snapshot(viewer, "tasks").people, &(&1.id == teammate.id)).here
  end

  test "owner loss cleans up only its own lease even after an untrappable exit", %{conn: conn} do
    {_, user} = log_in_user(conn)
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()
    assert {:ok, _} = Presence.sync(user, first, %{"resource" => "people"})
    assert {:ok, _} = Presence.sync(user, second, %{"resource" => "tasks"})
    supervisor = start_supervised!(Task.Supervisor)
    test_pid = self()

    owner =
      Task.Supervisor.async_nolink(supervisor, fn ->
        {:ok, tracker} = Presence.track(user, first)
        send(test_pid, {:tracking, tracker})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:tracking, tracker}
    ref = Process.monitor(tracker)
    Process.exit(owner.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^tracker, :normal}
    refute Repo.exists?(from c in Connection, where: c.user_id == ^user.id and c.connection_id == ^first)
    assert Repo.exists?(from c in Connection, where: c.user_id == ^user.id and c.connection_id == ^second)
  end

  test "exact records require current read access and existence", %{conn: conn} do
    {_, restricted} = log_in_user(conn)
    {_, reader} = log_in_user(conn, %{scopes: ["accounts:read"]})
    {:ok, account} = Accounts.create_manual_account(%{name: "Presence test"})
    params = %{"resource" => "accounts", "id" => account.id}
    assert {:error, :forbidden} = Presence.sync(restricted, Ecto.UUID.generate(), params)
    assert {:error, :not_found} = Presence.location(reader, %{params | "id" => Ecto.UUID.generate()})
    assert {:ok, _} = Presence.sync(reader, Ecto.UUID.generate(), params)
    assert {:error, :invalid_params} = Presence.location(reader, %{"path" => "/admin"})
    assert {:error, :invalid_params} = Presence.location(reader, %{"resource" => "people", "id" => account.id})
  end
end
