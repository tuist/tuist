defmodule TuistWeb.PresenceChannelTest do
  use TuistWeb.ChannelCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Halls
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.PresenceChannel
  alias TuistWeb.ThreadsSocket

  setup do
    stub(FeatureFlags, :guild_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_guild_enabled?, fn _ -> true end)
    ana = AccountsFixtures.user_fixture(preload: [:account])
    ben = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: ana)
    :ok = Accounts.add_user_to_organization(ben, organization, role: :user)
    account = Accounts.get_account_from_organization(organization)
    %{ana: ana, ben: ben, account: account, topic: "presence:#{account.name}"}
  end

  test "members see who in the organization is connected, live", %{ana: ana, ben: ben, account: account, topic: topic} do
    ana_socket = join!(ana, topic)
    ana_id = to_string(ana.id)
    ben_id = to_string(ben.id)
    assert_push "presence_state", %{^ana_id => %{metas: [%{handle: handle}]}}
    assert handle == ana.account.name

    ben_socket = join!(ben, topic)
    assert_push "presence_state", %{^ana_id => _, ^ben_id => _}
    assert_push "presence_diff", %{joins: %{^ben_id => _}}

    # HTTP clients without a socket see the same thing.
    assert {:ok, people} = Halls.people(ana, account)
    assert [%{id: id, online: true}] = people
    assert id == ben.id

    Process.unlink(ben_socket.channel_pid)
    close(ben_socket)
    assert_push "presence_diff", %{leaves: %{^ben_id => _}}
    assert {:ok, [%{online: false}]} = Halls.people(ana, account)
    assert ana_socket
  end

  test "people outside the organization can neither join nor be seen", %{topic: topic} do
    stranger = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, socket} = connect(ThreadsSocket, %{}, connect_info: %{auth_token: token(stranger)})
    assert {:error, %{reason: "not_found"}} = subscribe_and_join(socket, PresenceChannel, topic)
    assert {:error, %{reason: "not_found"}} = subscribe_and_join(socket, PresenceChannel, "presence:missing-org")
  end

  test "an organization whose handle is another's ID receives none of its presence", %{ana: ana, account: account} do
    eve = AccountsFixtures.user_fixture(preload: [:account])
    numeric = AccountsFixtures.organization_fixture(creator: eve, name: to_string(account.id))
    numeric_account = Accounts.get_account_from_organization(numeric)
    assert numeric_account.name == to_string(account.id)

    _eve_socket = join!(eve, "presence:#{numeric_account.name}")
    _ana_socket = join!(ana, "presence:#{account.name}")
    # Both sockets push to this process; only the numeric organization's matter.
    leaked = "presence:#{numeric_account.name}"
    ana_id = to_string(ana.id)

    refute_receive %Phoenix.Socket.Message{topic: ^leaked, event: "presence_diff", payload: %{joins: %{^ana_id => _}}},
                   300
  end

  test "losing access disconnects and untracks the member", %{ana: ana, ben: ben, account: account, topic: topic} do
    _ana_socket = join!(ana, topic)
    ben_socket = join!(ben, topic)
    ben_id = to_string(ben.id)
    Process.unlink(ben_socket.channel_pid)
    ref = Process.monitor(ben_socket.channel_pid)

    stub(FeatureFlags, :guild_enabled?, fn user -> user.id != ben.id end)
    send(ben_socket.channel_pid, :recheck)

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert_push "presence_diff", %{leaves: %{^ben_id => _}}
    assert {:ok, [%{online: false}]} = Halls.people(ana, account)
  end

  defp join!(user, topic) do
    {:ok, socket} = connect(ThreadsSocket, %{}, connect_info: %{auth_token: token(user)})
    {:ok, _, socket} = subscribe_and_join(socket, PresenceChannel, topic)
    socket
  end

  defp token(user) do
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    token
  end
end
