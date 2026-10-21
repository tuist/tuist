defmodule AtlasWeb.PresenceChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.ChannelTest

  alias Atlas.Guardian
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Presence
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

  test "missing tokens cannot open a socket and restricted locations cannot join", %{conn: conn} do
    assert :error = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{})
    {_, user} = log_in_user(conn)
    token = oauth_access_token_fixture(user)
    assert {:ok, socket} = Phoenix.ChannelTest.connect(PresenceSocket, %{}, connect_info: %{auth_token: token})

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, PresenceChannel, "presence:team", %{"resource" => "invoices"})
  end
end
