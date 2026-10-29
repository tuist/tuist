defmodule AtlasWeb.LayoutLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Demo
  alias Atlas.Users
  alias AtlasWeb.AccountsLive
  alias AtlasWeb.Endpoint
  alias AtlasWeb.LayoutLive
  alias AtlasWeb.Router
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

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
