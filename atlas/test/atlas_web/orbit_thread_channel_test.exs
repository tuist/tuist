defmodule AtlasWeb.OrbitThreadChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.OrbitFixtures
  import Phoenix.ChannelTest

  alias Atlas.OAuth.AccessTokens
  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Progress
  alias Atlas.Orbit.Run
  alias Atlas.Repo
  alias AtlasWeb.OrbitThreadChannel
  alias AtlasWeb.PresenceSocket

  setup do
    owner = user_fixture()
    member = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})
    %{owner: owner, member: member, thread: thread}
  end

  test "join returns viewers including the caller, and typing reaches other viewers", context do
    %{owner: owner, member: member, thread: thread} = context
    {owner_socket, _} = join_as(owner, thread)

    assert {:ok, snapshot, member_socket} =
             socket_for(member)
             |> subscribe_and_join(OrbitThreadChannel, "orbit:thread:#{thread.id}", %{})

    assert snapshot.revision == thread.last_seq
    assert snapshot.people |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([owner.id, member.id])
    assert Enum.all?(snapshot.people, &(&1.typing == false))
    assert snapshot.agent_status == "unconfigured"

    ref = Phoenix.ChannelTest.push(member_socket, "typing", %{"typing" => true})
    assert_reply ref, :ok
    send(owner_socket.channel_pid, :thread_changed)
    people = await_snapshot(fn snapshot -> Enum.find(snapshot.people, &(&1.id == member.id && &1.typing)) end).people
    assert Enum.all?(people, &(Map.keys(&1) |> Enum.sort() == [:id, :name, :typing]))
  end

  test "compaction activity pushes even when history revision is unchanged", %{owner: owner, thread: thread} do
    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        acting_user_id: owner.id,
        status: "running",
        trigger_seq: 0,
        session_id: Ecto.UUID.generate()
      })

    {socket, initial} = join_as(owner, thread)
    assert initial.agent_status == "running"
    metadata = %{agent: Agent, session_id: run.session_id}
    Progress.handle_event([:condukt, :compact, :start], %{}, metadata, nil)
    send(socket.channel_pid, :thread_changed)
    assert %{revision: revision} = await_snapshot(&(&1.agent_status == "compacting"))
    assert revision == initial.revision

    Progress.handle_event([:condukt, :compact, :stop], %{}, Map.put(metadata, :changed, false), nil)
    send(socket.channel_pid, :thread_changed)
    assert %{revision: ^revision} = await_snapshot(&(&1.agent_status == "running"))
  end

  test "new messages move the revision", %{owner: owner, thread: thread} do
    {socket, snapshot} = join_as(owner, thread)

    {:ok, _message, :created} =
      Orbit.post_message(owner, thread, %{
        "body" => "Hi",
        "client_id" => Ecto.UUID.generate(),
        "address_agent" => false
      })

    send(socket.channel_pid, :thread_changed)
    assert await_snapshot(&(&1.revision > snapshot.revision))
  end

  test "non-participants cannot join and removed participants are disconnected", context do
    %{owner: owner, member: member, thread: thread} = context
    outsider = user_fixture(Atlas.Authorization.executive_scopes())

    assert {:error, %{reason: "unavailable"}} =
             outsider |> socket_for() |> subscribe_and_join(OrbitThreadChannel, "orbit:thread:#{thread.id}", %{})

    {socket, _} = join_as(member, thread)
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    :ok = Orbit.remove_participant(owner, thread, member.id)
    send(socket.channel_pid, :thread_changed)
    assert_receive {:DOWN, ^monitor, :process, _, _}
  end

  test "revoked OAuth grants stop the channel", %{owner: owner, thread: thread} do
    token = oauth_access_token_fixture(owner)
    {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _, socket} = subscribe_and_join(socket, OrbitThreadChannel, "orbit:thread:#{thread.id}", %{})
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: token))
    send(socket.channel_pid, :renew)
    assert_receive {:DOWN, ^monitor, :process, _, _}
  end

  describe "orbit:me" do
    test "pushes an id-free revision when an authorized thread appears", %{owner: owner} do
      {:ok, initial, socket} =
        owner |> socket_for() |> subscribe_and_join(AtlasWeb.OrbitInboxChannel, "orbit:me", %{})

      assert %{revision: revision, people: []} = initial
      assert is_integer(revision) and revision >= 0

      {:ok, created} =
        Orbit.create_shared(user_fixture(), %{"title" => "Signal", "participant_ids" => [owner.id]})

      send(socket.channel_pid, :renew)
      snapshot = await_snapshot(&(&1.revision != revision))
      assert snapshot.people == []
      refute inspect(snapshot) =~ created.id
    end

    test "other people's threads do not move the revision", %{owner: owner} do
      {:ok, initial, socket} =
        owner |> socket_for() |> subscribe_and_join(AtlasWeb.OrbitInboxChannel, "orbit:me", %{})

      stranger = user_fixture()
      {:ok, _private, _} = Orbit.ensure_private(stranger)
      send(socket.channel_pid, :renew)
      refute_push "snapshot", _, 200
      assert Orbit.list_revision(owner) == initial.revision
    end

    test "revoked OAuth grants stop the list channel", %{owner: owner} do
      token = oauth_access_token_fixture(owner)
      {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})
      {:ok, _, socket} = subscribe_and_join(socket, AtlasWeb.OrbitInboxChannel, "orbit:me", %{})
      Process.unlink(socket.channel_pid)
      monitor = Process.monitor(socket.channel_pid)
      {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: token))
      send(socket.channel_pid, :renew)
      assert_receive {:DOWN, ^monitor, :process, _, _}
    end
  end

  # Earlier invalidations may already have pushed snapshots; wait for the one
  # that satisfies the condition.
  defp await_snapshot(matches?) do
    assert_push "snapshot", snapshot
    if matches?.(snapshot), do: snapshot, else: await_snapshot(matches?)
  end

  defp socket_for(user) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: oauth_access_token_fixture(user)})

    socket
  end

  defp join_as(user, thread) do
    {:ok, snapshot, socket} =
      user |> socket_for() |> subscribe_and_join(OrbitThreadChannel, "orbit:thread:#{thread.id}", %{})

    {socket, snapshot}
  end
end
