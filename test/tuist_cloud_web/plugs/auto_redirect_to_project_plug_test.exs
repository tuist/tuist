defmodule TuistCloudWeb.AutoRedirectToProjectPlugTest do
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  use Plug.Test
  use TuistCloudWeb.ConnCase
  alias TuistCloudWeb.AutoRedirectToProjectPlug
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Accounts

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preloads: [:account])

    %{
      current_user: user,
      conn: conn |> Authentication.put_current_user(user),
      plug_opts: AutoRedirectToProjectPlug.init(%{})
    }
  end

  test "redirects to the first user project if no project has been visited before", %{
    conn: conn,
    current_user: current_user,
    plug_opts: plug_opts
  } do
    # When
    project = ProjectsFixtures.project_fixture(account_id: current_user.account.id)
    conn = conn |> AutoRedirectToProjectPlug.call(plug_opts)

    # Then
    assert redirected_to(conn) == "/#{current_user.account.name}/#{project.name}"
  end

  test "redirects to the last visited project if present", %{
    conn: conn,
    current_user: current_user,
    plug_opts: plug_opts
  } do
    # When
    project = ProjectsFixtures.project_fixture(account_id: current_user.account.id)
    current_user = current_user |> Accounts.update_last_visited_project(project.id)
    conn = conn |> AutoRedirectToProjectPlug.call(plug_opts)

    # Then
    assert redirected_to(conn) == "/#{current_user.account.name}/#{project.name}"
  end

  test "redirects to the user projects if the user has no projects", %{
    conn: conn,
    current_user: current_user,
    plug_opts: plug_opts
  } do
    # When
    conn = conn |> AutoRedirectToProjectPlug.call(plug_opts)

    # Then
    assert redirected_to(conn) == ~p"/#{current_user.account.name}/projects"
  end

  test "returns the same connection for any path", %{
    current_user: _,
    plug_opts: plug_opts
  } do
    # Given
    conn = build_conn(:get, "/random-path", nil)

    # When
    got = conn |> AutoRedirectToProjectPlug.call(plug_opts)

    # Then
    assert got == conn
  end
end
