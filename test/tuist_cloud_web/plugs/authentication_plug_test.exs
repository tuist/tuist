defmodule TuistCloudWeb.AuthenticationPlugTest do
  use TuistCloud.DataCase
  use Plug.Test
  alias TuistCloudWeb.AuthenticationPlug
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.ProjectsFixtures

  test "loads the authenticated user" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    user = AccountsFixtures.user_fixture()
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> user.token)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistCloudWeb.Authentication.current_user(got).id == user.id
    assert TuistCloudWeb.Authentication.authenticated?(got) == true
  end

  test "loads the authenticated project" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    project = ProjectsFixtures.project_fixture()
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> project.token)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistCloudWeb.Authentication.current_project(got).id == project.id
    assert TuistCloudWeb.Authentication.authenticated?(got) == true
  end

  test "doesn't load anything if the token is absent" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    conn = conn(:get, "/")

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistCloudWeb.Authentication.current_project(got) == nil
    assert TuistCloudWeb.Authentication.current_user(got) == nil
    assert TuistCloudWeb.Authentication.authenticated?(got) == false
  end

  test "doesn't load anything if the the token is invalid" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> "invalid-token")

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistCloudWeb.Authentication.current_project(got) == nil
    assert TuistCloudWeb.Authentication.current_user(got) == nil
    assert TuistCloudWeb.Authentication.authenticated?(got) == false
  end
end
