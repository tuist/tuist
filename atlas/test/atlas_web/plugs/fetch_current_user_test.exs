defmodule AtlasWeb.Plugs.FetchCurrentUserTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Demo
  alias Atlas.Users
  alias AtlasWeb.Plugs.FetchCurrentUser

  setup :verify_on_exit!

  test "demo requests never load a session user", %{conn: conn} do
    stub(Demo, :enabled?, fn -> true end)
    reject(Users, :get_user, 1)

    conn =
      conn
      |> Plug.Test.init_test_session(%{"user_id" => Uniq.UUID.uuid7()})
      |> FetchCurrentUser.call([])

    assert conn.assigns.current_user == Demo.user()
  end

  test "production requests retain the real session user", %{conn: conn} do
    stub(Demo, :enabled?, fn -> false end)
    {conn, user} = log_in_user(conn)
    conn = FetchCurrentUser.call(conn, [])
    assert conn.assigns.current_user.id == user.id
  end

  test "production requests without a session never get a demo identity", %{conn: conn} do
    stub(Demo, :enabled?, fn -> false end)
    conn = conn |> Plug.Test.init_test_session(%{}) |> FetchCurrentUser.call([])
    assert conn.assigns.current_user == nil
  end
end
