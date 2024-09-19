defmodule TuistWeb.SuperAdminOnlyPlugTest do
  use TuistWeb.ConnCase, async: true
  use Plug.Test
  use Mimic

  import TuistWeb.Gettext

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.SuperAdminOnlyPlug
  alias Tuist.AccountsFixtures

  test "return the same connection when it's not production", %{conn: conn} do
    # Given
    opts = SuperAdminOnlyPlug.init(%{})

    # When/Then
    for env <- Environment.all_envs() do
      case env do
        :prod ->
          :ok

        _ ->
          Environment |> stub(:env, fn -> env end)
          assert SuperAdminOnlyPlug.call(conn, opts) == conn
      end
    end
  end

  test "returns the same connection when it's production and the authenticated user is super admin",
       %{conn: conn} do
    # Given
    opts = SuperAdminOnlyPlug.init(%{})
    user = AccountsFixtures.user_fixture(preloads: [:account])
    Environment |> stub(:env, fn -> :prod end)
    Environment |> stub(:super_admin_user_ids, fn -> [user.id] end)
    conn = conn |> Authentication.put_current_user(user)

    # When
    assert SuperAdminOnlyPlug.call(conn, opts) == conn
  end

  test "raises an error when no authenticated user and production",
       %{conn: conn} do
    # Given
    opts = SuperAdminOnlyPlug.init(%{})
    user = AccountsFixtures.user_fixture(preloads: [:account])
    Environment |> stub(:env, fn -> :prod end)

    # When
    assert_raise RuntimeError, gettext("You are not authorized to visit this page."), fn ->
      SuperAdminOnlyPlug.call(conn, opts)
    end
  end

  test "raises an error when not super-admin user authenticated and production",
       %{conn: conn} do
    # Given
    opts = SuperAdminOnlyPlug.init(%{})
    user = AccountsFixtures.user_fixture(preloads: [:account])
    Environment |> stub(:env, fn -> :prod end)
    Environment |> stub(:super_admin_user_ids, fn -> [] end)
    conn = conn |> Authentication.put_current_user(user)

    # When
    assert_raise RuntimeError, gettext("You are not authorized to visit this page."), fn ->
      SuperAdminOnlyPlug.call(conn, opts)
    end
  end
end
