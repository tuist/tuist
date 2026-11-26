defmodule AtlasWeb.LayoutLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Demo
  alias Atlas.Engineering.Domains
  alias Atlas.Users
  alias AtlasWeb.AccountsLive
  alias AtlasWeb.Endpoint
  alias AtlasWeb.LayoutLive
  alias AtlasWeb.Router
  alias Phoenix.Channel.Server
  alias Phoenix.LiveView.Channel
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Reply

  require Phoenix.ChannelTest

  setup :verify_on_exit!

  setup do
    stub(Demo, :enabled?, fn -> false end)
    :ok
  end

  test "production LiveView mounts reject missing, stale, and demo identities" do
    for session <- [%{}, %{"user_id" => Uniq.UUID.uuid7()}, %{"user_id" => Demo.user().id}],
        mount <- [:default, {:scope, "finance:read"}, {:scope, "admin:read"}] do
      assert {:halt, socket} = LayoutLive.on_mount(mount, %{}, session, socket())
      assert {:redirect, %{to: "/login"}} = socket.redirected
      refute Map.has_key?(socket.assigns, :current_user)
    end
  end

  test "production users receive no implicit demo scopes", %{conn: conn} do
    {_conn, user} = log_in_user(conn)
    assert Users.scopes_for(user) == []

    for scope <-
          ~w(accounts:read finance:read notes:read documents:read letters:read licenses:read assets:read insurance:read admin:read) do
      refute Users.has_scope?(user, scope)
      assert {:halt, socket} = LayoutLive.on_mount({:scope, scope}, %{}, %{"user_id" => user.id}, socket())
      assert {:redirect, %{to: "/commercial/sales"}} = socket.redirected
    end
  end

  test "production mounts retain assigned scopes and the real session user", %{conn: conn} do
    {_conn, user} = log_in_user(conn, %{scopes: ["finance:write"]})
    assert Users.has_scope?(user, "finance:read")
    assert Users.has_scope?(user, "finance:write")
    refute Users.admin?(user)

    assert {:cont, socket} =
             LayoutLive.on_mount({:scope, "finance:read"}, %{}, %{"user_id" => user.id}, socket())

    assert socket.assigns.current_user.id == user.id
    refute Map.has_key?(socket.assigns, :demo_mode)
    refute Enum.any?(socket.private.lifecycle.handle_event, &(&1.id == :demo_events))
  end

  test "production administrators keep their stored privileges", %{conn: conn} do
    {_conn, user} = log_in_user(conn, %{role: :executive})
    assert Users.admin?(user)

    assert {:cont, socket} = LayoutLive.on_mount({:scope, "admin:read"}, %{}, %{"user_id" => user.id}, socket())
    assert socket.assigns.current_user.id == user.id
    refute Map.has_key?(socket.assigns, :demo_mode)
  end

  test "demo LiveView mounts ignore session identities and attach read-only guards" do
    stub(Demo, :enabled?, fn -> true end)
    reject(Users, :get_user, 1)

    assert {:cont, socket, _opts} =
             LayoutLive.on_mount(:default, %{}, %{"user_id" => Uniq.UUID.uuid7()}, socket())

    assert socket.assigns.current_user == Demo.user()
    assert socket.assigns.demo_mode
    assert Enum.any?(socket.private.lifecycle.handle_event, &(&1.id == :demo_events))
    assert Enum.any?(socket.private.lifecycle.handle_params, &(&1.id == :demo_paths))
    assert Users.scopes_for(socket.assigns.current_user) == Demo.scopes()
    refute Users.admin?(socket.assigns.current_user)

    for scope <- ~w(accounts:write finance:write notes:write documents:read admin:read admin:write) do
      refute Users.has_scope?(socket.assigns.current_user, scope)
    end
  end

  # GHSA-v4p7-3pm2-wq6c: before phoenix_live_view 1.1.34 a phx_join without a
  # "url" key mounted a router LiveView without its live_session on_mount hooks,
  # so a user removed after the page loaded could keep using its session token.
  test "a socket join without a url is refused instead of skipping the live_session hooks", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    conn = get(conn, ~p"/engineering/domains")
    cookie_session = get_session(conn)
    {id, session_token, static_token} = main_live_view(html_response(conn, 200))

    {:ok, _user} = Users.delete_user(user)

    socket = Phoenix.ChannelTest.socket(Socket, nil, %{}, [])
    # A real websocket stores the cookie session here when it connects.
    socket = put_in(socket.private[:connect_info], %{session: cookie_session})

    join_params = %{
      "session" => session_token,
      "static" => static_token,
      "params" => %{"_csrf_token" => cookie_session["_csrf_token"], "_mounts" => 0}
    }

    result = join_live_view(socket, "lv:" <> id, join_params)

    with {:ok, _reply, pid} <- result do
      send(pid, %Message{
        topic: "lv:" <> id,
        event: "event",
        ref: "1",
        payload: %{"type" => "form", "event" => "save", "value" => "domain[name]=Revoked&domain[visibility]=public"}
      })

      assert_receive %Reply{ref: "1", status: :ok}
    end

    refute Enum.any?(Domains.list_domains(), &(&1.name == "Revoked"))
    assert {:error, %{reason: "unauthorized"}} = result
  end

  # Phoenix.ChannelTest.join/4 asks the channel for its socket afterwards, a
  # call LiveView channels don't answer, so join through the server directly.
  defp join_live_view(%{private: %{phoenix_test_supervisor: sup}} = socket, topic, payload) do
    message = %Message{event: "phx_join", topic: topic, payload: payload, ref: "0"}
    starter = fn _, _, spec -> Supervisor.start_child(sup, %{spec | id: make_ref()}) end
    Server.join(socket, Channel, message, starter: starter)
  end

  defp main_live_view(html) do
    [main] = html |> LazyHTML.from_document() |> LazyHTML.query("[data-phx-main]") |> Enum.to_list()

    {hd(LazyHTML.attribute(main, "id")), hd(LazyHTML.attribute(main, "data-phx-session")),
     hd(LazyHTML.attribute(main, "data-phx-static"))}
  end

  defp socket do
    %Socket{
      endpoint: Endpoint,
      router: Router,
      view: AccountsLive,
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}, lifecycle: %Lifecycle{}}
    }
  end
end
