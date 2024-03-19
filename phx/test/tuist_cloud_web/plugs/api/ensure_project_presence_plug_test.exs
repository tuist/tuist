defmodule TuistCloudWeb.API.EnsureProjectPresencePlugTest do
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  use TuistCloudWeb.ConnCase
  use Plug.Test
  alias TuistCloudWeb.API.EnsureProjectPresencePlug

  test "loads and assigns the project to the connection if it exists" do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    opts = EnsureProjectPresencePlug.init([])
    conn = build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert EnsureProjectPresencePlug.get_project(conn) == project
  end

  test "errors and halts the connection if the project is not found" do
    # Given
    opts = EnsureProjectPresencePlug.init([])
    conn = build_conn(:get, ~p"/api/cache", project_id: "non/existing")

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert conn.halted == true
    assert json_response(conn, 404) == %{"message" => "The project was not found"}
  end
end
