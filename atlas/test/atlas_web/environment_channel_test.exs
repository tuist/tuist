defmodule AtlasWeb.EnvironmentChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.EnvironmentFixtures
  import Atlas.OrbitFixtures
  import Atlas.PushFixtures, only: [native_access_token: 1]
  import Phoenix.ChannelTest

  alias Atlas.Environments
  alias Atlas.Environments.Commands
  alias Atlas.OAuth.AccessTokens
  alias AtlasWeb.EnvironmentChannel
  alias AtlasWeb.PresenceSocket

  setup do
    environment_fixture()
  end

  test "reconciles authoritative snapshots without a cross-replica hint; claimed calls disappear", c do
    assert {:ok, %{commands: []}, socket} = join_device(c.token, c.environment.id)
    command = command_fixture(c)
    send(socket.channel_pid, :reconcile)
    assert_push "snapshot", %{commands: [%{id: id}]}
    assert id == command.id
    claim_fixture(c, command)
    send(socket.channel_pid, :reconcile)
    assert_push "snapshot", %{commands: []}
  end

  test "non-native clients, another client of the same owner, and other owners cannot join", c do
    assert {:error, %{reason: "unavailable"}} = join_device(oauth_access_token_fixture(c.user), c.environment.id)
    {_client, token} = native_access_token(c.user)
    assert {:error, %{reason: "unavailable"}} = join_device(token, c.environment.id)
    {_client, token} = native_access_token(user_fixture())
    assert {:error, %{reason: "unavailable"}} = join_device(token, c.environment.id)
  end

  test "delivery payloads are not retained in inspectable channel crash state", c do
    command_fixture(c)
    assert {:ok, %{commands: [%{arguments: %{"path" => "README.md"}}]}, socket} = join_device(c.token, c.environment.id)
    refute inspect(:sys.get_state(socket.channel_pid)) =~ "README.md"
  end

  test "disable stops pushes and stale renewals cannot make the environment online", c do
    {:ok, _, socket} = join_device(c.token, c.environment.id)
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    assert {:ok, _} = Environments.disable(c.user, c.client_id, c.environment.id)
    send(socket.channel_pid, :reconcile)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    assert [%{online: false, enabled: false}] = Environments.list(c.user).environments
    refute_push "snapshot", _
  end

  test "revoked grants close the channel and fence dispatch", c do
    {:ok, _, socket} = join_device(c.token, c.environment.id)
    command = command_fixture(c)
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: c.token))
    send(socket.channel_pid, :reconcile)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    assert {:error, :environment_disabled} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert command.id
  end

  defp join_device(token, id) do
    {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})
    subscribe_and_join(socket, EnvironmentChannel, "environment:#{id}", %{})
  end
end
