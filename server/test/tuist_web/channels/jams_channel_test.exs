defmodule TuistWeb.JamsChannelTest do
  use TuistWeb.ChannelCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Jams.Jam
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.JamsChannel
  alias TuistWeb.JamsSocket

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    %{user: user, token: token, topic: "jams:#{user.account.name}:inbox"}
  end

  test "never authenticates tokens supplied in URL params", %{token: token} do
    assert :error = connect(JamsSocket, %{"token" => token})
  end

  test "accepts the Phoenix bearer subprotocol extraction", %{token: token} do
    assert {:ok, _socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
  end

  test "the endpoint hands the native clients' bearer subprotocol to the socket", %{token: token} do
    handshake = fn collection, credential ->
      :get
      |> Plug.Test.conn("/#{collection}/socket/websocket?vsn=2.0.0")
      |> Plug.Conn.put_req_header("connection", "Upgrade")
      |> Plug.Conn.put_req_header("upgrade", "websocket")
      |> Plug.Conn.put_req_header("sec-websocket-version", "13")
      |> Plug.Conn.put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
      |> Plug.Conn.put_req_header(
        "sec-websocket-protocol",
        "phoenix, base64url.bearer.phx." <> Base.url_encode64(credential, padding: false)
      )
      |> TuistWeb.Endpoint.call([])
    end

    # A refused connect answers 403. An accepted one proceeds to the upgrade,
    # which the test adapter cannot perform and answers with 400.
    for collection <- ["jams", "threads"] do
      assert handshake.(collection, "not-a-token").status == 403
      assert handshake.(collection, token).status == 400
    end
  end

  test "rejects a genuinely expired user JWT", %{user: user} do
    {:ok, expired, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token", ttl: {-60, :second})
    assert :error = connect(JamsSocket, %{}, connect_info: %{auth_token: expired})
  end

  test "only the allowed native OAuth client can connect", %{user: user} do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    native = oauth_token(user, Clients.public!())
    {:ok, other_client} = Clients.create_client(%{redirect_uris: ["https://example.com/callback"], name: "other"})
    other = oauth_token(user, other_client)
    assert {:ok, _socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: native})
    assert :error = connect(JamsSocket, %{}, connect_info: %{auth_token: other})
  end

  test "shared account credentials cannot subscribe", %{user: user} do
    {:ok, {_, token}} =
      Accounts.create_account_token(%{account: user.account, scopes: ["account:cache:read"], name: "jams"})

    assert :error = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
  end

  test "inbox snapshots contain only invalidation metadata", %{token: token, topic: topic} do
    for topic <- [topic, String.replace_prefix(topic, "jams:", "threads:")] do
      {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
      assert {:ok, snapshot, _socket} = subscribe_and_join(socket, topic)
      assert snapshot |> Map.keys() |> Enum.sort() == [:agent_status, :revision]
    end
  end

  test "denies foreign accounts and malformed IDs", %{token: token, user: user} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, JamsChannel, "jams:#{other.account.name}:inbox")

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, JamsChannel, "jams:#{user.account.name}:invalid")
  end

  test "polling revalidates a deactivated user even without PubSub", %{token: token, topic: topic, user: user} do
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _snapshot, socket} = subscribe_and_join(socket, JamsChannel, topic)
    user |> Ecto.Changeset.change(active: false) |> Repo.update!()
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :poll_snapshot)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_push "snapshot", _
  end

  test "notifications also revalidate before exposing a snapshot", %{token: token, topic: topic, user: user} do
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _snapshot, socket} = subscribe_and_join(socket, JamsChannel, topic)
    user |> Ecto.Changeset.change(active: false) |> Repo.update!()
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :jams_changed)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_push "snapshot", _
  end

  test "flag withdrawal closes a previously authorized subscription", %{token: token, topic: topic} do
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _, socket} = subscribe_and_join(socket, JamsChannel, topic)
    stub(FeatureFlags, :ai_enabled?, fn _user -> false end)
    allow(FeatureFlags, self(), socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :poll_snapshot)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_push "snapshot", _
  end

  test "polling rechecks token verification instead of retaining the join identity", %{token: token, topic: topic} do
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _, socket} = subscribe_and_join(socket, JamsChannel, topic)
    stub(Tuist.Guardian, :resource_from_token, fn ^token -> {:error, :token_expired} end)
    allow(Tuist.Guardian, self(), socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :poll_snapshot)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_push "snapshot", _
  end

  test "native OAuth grant revocation closes a live subscription", %{user: user, topic: topic} do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    native = oauth_token(user, Clients.public!())
    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: native})
    {:ok, _, socket} = subscribe_and_join(socket, JamsChannel, topic)
    Token |> Repo.get_by!(value: native) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :poll_snapshot)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_push "snapshot", _
  end

  test "authoritative polling repairs a lost cross-replica notification", %{user: user, token: token} do
    jam =
      Repo.insert!(%Jam{
        account_id: user.account.id,
        owner_id: user.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.hash(:sha256, "test"),
        title: "Private title",
        provider: "chatgpt",
        model: "selected-model",
        goal: "Private prompt"
      })

    {:ok, socket} = connect(JamsSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _, socket} = subscribe_and_join(socket, JamsChannel, "jams:#{user.account.name}:#{jam.id}")
    jam |> Ecto.Changeset.change(revision: 1, agent_status: "running") |> Repo.update!()
    send(socket.channel_pid, :poll_snapshot)
    assert_push "snapshot", %{revision: 1, agent_status: "running"}, 1_000
  end

  defp oauth_token(user, client) do
    token = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: token,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    token
  end
end
