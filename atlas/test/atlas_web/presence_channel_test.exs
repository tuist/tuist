defmodule AtlasWeb.PresenceChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.ChannelTest

  alias Atlas.Accounts
  alias Atlas.Authorization.Roles
  alias Atlas.Guardian
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Presence
  alias Atlas.Presence.Connection
  alias Atlas.Repo
  alias AtlasWeb.PresenceChannel
  alias AtlasWeb.PresenceSocket

  test "endpoint authenticates the actual WebSocket bearer subprotocol", %{conn: conn} do
    {_, user} = log_in_user(conn)
    token = oauth_access_token_fixture(user)

    conn =
      %{conn | req_headers: [{"host", conn.host} | conn.req_headers]}
      |> put_req_header("connection", "upgrade")
      |> put_req_header("upgrade", "websocket")
      |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
      |> put_req_header("sec-websocket-version", "13")
      |> put_req_header(
        "sec-websocket-protocol",
        "phoenix, base64url.bearer.phx.#{Base.url_encode64(token, padding: false)}"
      )
      |> get("/presence/websocket?vsn=2.0.0")

    assert conn.state == :upgraded
    assert get_resp_header(conn, "sec-websocket-protocol") == ["phoenix"]
  end

  test "authenticated channel pushes another person's arrival and rejects revoked tokens", %{conn: conn} do
    {_, user} = log_in_user(conn)
    {_, teammate} = log_in_user(conn)
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:ok, initial, socket} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{"resource" => "tasks"})

    refute Enum.find(initial.people, &(&1.id == teammate.id)).online
    assert {:ok, _} = Presence.sync(teammate, Ecto.UUID.generate(), %{"resource" => "tasks"})
    send(socket.channel_pid, :presence_changed)
    assert_push "snapshot", %{people: people}
    assert Enum.find(people, &(&1.id == teammate.id)).here

    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "people"})
    assert_reply ref, :ok, %{people: people}
    refute Enum.find(people, &(&1.id == teammate.id)).here
    assert {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: token))
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :renew_presence)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute Enum.find(Presence.snapshot(teammate).people, &(&1.id == user.id)).online
    assert {:error, _} = Guardian.resource_from_token(token)
  end

  test "missing tokens and malformed locations are still rejected", %{conn: conn} do
    assert :error = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{})
    {_, user} = log_in_user(conn)
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{"path" => "/admin"})
  end

  test "restricted joins and updates retain availability without disclosing same-location hints", %{conn: conn} do
    {_, user} = log_in_user(conn)
    {_, reader} = log_in_user(conn, %{scopes: ["finance:read"]})
    assert {:ok, _} = Presence.sync(reader, Ecto.UUID.generate(), %{"resource" => "invoices"})
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:ok, initial, socket} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{"resource" => "invoices"})

    assert Enum.find(initial.people, &(&1.id == user.id)).online
    refute Enum.any?(initial.people, & &1.here)
    assert Repo.one!(from c in Connection, where: c.user_id == ^user.id).location == nil

    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "tasks"})
    assert_reply ref, :ok, _
    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "invoices"})
    assert_reply ref, :ok, %{people: people}
    assert Enum.find(people, &(&1.id == user.id)).online
    refute Enum.any?(people, & &1.here)
    assert Repo.one!(from c in Connection, where: c.user_id == ^user.id).location == nil

    send(socket.channel_pid, :renew_presence)
    _ = :sys.get_state(socket.channel_pid)
    assert Enum.find(Presence.snapshot(reader, "invoices").people, &(&1.id == user.id)).online
    refute Enum.find(Presence.snapshot(reader, "invoices").people, &(&1.id == user.id)).here

    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "people"})
    assert_reply ref, :ok, _
    assert Repo.one!(from c in Connection, where: c.user_id == ^user.id).location == "people"
  end

  test "deleting the current record clears its location without disconnecting", %{conn: conn} do
    {_, user} = log_in_user(conn, %{scopes: ["accounts:read"]})
    {:ok, account} = Accounts.create_manual_account(%{name: "Presence record"})
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:ok, _, socket} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{
               "resource" => "accounts",
               "id" => account.id
             })

    Repo.delete!(account)
    send(socket.channel_pid, :presence_changed)
    _ = :sys.get_state(socket.channel_pid)
    assert Repo.one!(from c in Connection, where: c.user_id == ^user.id).location == nil
    assert Enum.find(Presence.snapshot(user).people, &(&1.id == user.id)).online
    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "people"})
    assert_reply ref, :ok, _
  end

  test "renewal clears a revoked location while retaining authenticated availability", %{conn: conn} do
    {_, user} = log_in_user(conn, %{scopes: ["finance:read"]})
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:ok, _, socket} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{"resource" => "invoices"})

    assert {:ok, _} = Roles.set_user_roles(user, [])
    send(socket.channel_pid, :renew_presence)
    _ = :sys.get_state(socket.channel_pid)
    assert Repo.one!(from c in Connection, where: c.user_id == ^user.id).location == nil
    assert Enum.find(Presence.snapshot(user).people, &(&1.id == user.id)).online
    ref = Phoenix.ChannelTest.push(socket, "location", %{"resource" => "tasks"})
    assert_reply ref, :ok, _
  end
end
