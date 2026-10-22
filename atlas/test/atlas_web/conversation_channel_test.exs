defmodule AtlasWeb.ConversationChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.ConversationsFixtures
  import Phoenix.ChannelTest

  alias Atlas.Conversations
  alias Atlas.OAuth.AccessTokens
  alias AtlasWeb.ConversationChannel
  alias AtlasWeb.PresenceSocket

  setup do
    owner = user_fixture()
    member = user_fixture()
    {:ok, conversation} = Conversations.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})
    %{owner: owner, member: member, conversation: conversation}
  end

  test "join returns viewers including the caller, and typing reaches other viewers", context do
    %{owner: owner, member: member, conversation: conversation} = context
    {owner_socket, _} = join_as(owner, conversation)

    assert {:ok, snapshot, member_socket} =
             socket_for(member)
             |> subscribe_and_join(ConversationChannel, "conversation:#{conversation.id}", %{})

    assert snapshot.revision == conversation.last_seq
    assert snapshot.people |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([owner.id, member.id])
    assert Enum.all?(snapshot.people, &(&1.typing == false))
    assert snapshot.agent_status == "unconfigured"

    ref = Phoenix.ChannelTest.push(member_socket, "typing", %{"typing" => true})
    assert_reply ref, :ok
    send(owner_socket.channel_pid, :conversation_changed)
    people = await_snapshot(fn snapshot -> Enum.find(snapshot.people, &(&1.id == member.id && &1.typing)) end).people
    assert Enum.all?(people, &(Map.keys(&1) |> Enum.sort() == [:id, :name, :typing]))
  end

  test "new messages move the revision", %{owner: owner, conversation: conversation} do
    {socket, snapshot} = join_as(owner, conversation)

    {:ok, _message, :created} =
      Conversations.post_message(owner, conversation, %{
        "body" => "Hi",
        "client_id" => Ecto.UUID.generate(),
        "address_agent" => false
      })

    send(socket.channel_pid, :conversation_changed)
    assert await_snapshot(&(&1.revision > snapshot.revision))
  end

  test "non-participants cannot join and removed participants are disconnected", context do
    %{owner: owner, member: member, conversation: conversation} = context
    outsider = user_fixture(Atlas.Authorization.executive_scopes())

    assert {:error, %{reason: "unavailable"}} =
             outsider |> socket_for() |> subscribe_and_join(ConversationChannel, "conversation:#{conversation.id}", %{})

    {socket, _} = join_as(member, conversation)
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    :ok = Conversations.remove_participant(owner, conversation, member.id)
    send(socket.channel_pid, :conversation_changed)
    assert_receive {:DOWN, ^monitor, :process, _, _}
  end

  test "revoked OAuth grants stop the channel", %{owner: owner, conversation: conversation} do
    token = oauth_access_token_fixture(owner)
    {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _, socket} = subscribe_and_join(socket, ConversationChannel, "conversation:#{conversation.id}", %{})
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: token))
    send(socket.channel_pid, :renew)
    assert_receive {:DOWN, ^monitor, :process, _, _}
  end

  describe "conversations:me" do
    test "pushes an id-free revision when an authorized conversation appears", %{owner: owner} do
      {:ok, initial, socket} =
        owner |> socket_for() |> subscribe_and_join(AtlasWeb.ConversationListChannel, "conversations:me", %{})

      assert %{revision: revision, people: []} = initial
      assert is_integer(revision) and revision >= 0

      {:ok, created} =
        Conversations.create_shared(user_fixture(), %{"title" => "Signal", "participant_ids" => [owner.id]})

      send(socket.channel_pid, :renew)
      snapshot = await_snapshot(&(&1.revision != revision))
      assert snapshot.people == []
      refute inspect(snapshot) =~ created.id
    end

    test "other people's conversations do not move the revision", %{owner: owner} do
      {:ok, initial, socket} =
        owner |> socket_for() |> subscribe_and_join(AtlasWeb.ConversationListChannel, "conversations:me", %{})

      stranger = user_fixture()
      {:ok, _private, _} = Conversations.ensure_private(stranger)
      send(socket.channel_pid, :renew)
      refute_push "snapshot", _, 200
      assert Conversations.list_revision(owner) == initial.revision
    end

    test "revoked OAuth grants stop the list channel", %{owner: owner} do
      token = oauth_access_token_fixture(owner)
      {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})
      {:ok, _, socket} = subscribe_and_join(socket, AtlasWeb.ConversationListChannel, "conversations:me", %{})
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

  defp join_as(user, conversation) do
    {:ok, snapshot, socket} =
      user |> socket_for() |> subscribe_and_join(ConversationChannel, "conversation:#{conversation.id}", %{})

    {socket, snapshot}
  end
end
