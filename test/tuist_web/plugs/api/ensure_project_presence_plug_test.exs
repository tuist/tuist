defmodule TuistWeb.API.EnsureProjectPresencePlugTest do
  alias Tuist.Storage
  alias Tuist.CommandEventsFixtures
  alias Tuist.Accounts
  alias Tuist.ProjectsFixtures
  use TuistWeb.ConnCase
  use Plug.Test
  use Mimic
  alias TuistWeb.API.EnsureProjectPresencePlug

  test "loads and assigns the project to the connection if it exists" do
    # Given
    project = ProjectsFixtures.project_fixture(preloads: [:account])
    account = Accounts.get_account_by_id(project.account_id)
    opts = EnsureProjectPresencePlug.init([])
    conn = build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert EnsureProjectPresencePlug.get_project(conn) == project
  end

  test "loads and assigns the project to the connection if the command event and project exist" do
    # Given
    project = ProjectsFixtures.project_fixture(preloads: [:account])
    command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
    opts = EnsureProjectPresencePlug.init(:command_event)

    Storage
    |> expect(:multipart_start, fn _ ->
      "id"
    end)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> TuistWeb.Authentication.put_current_project(project)
      |> post(~p"/api/runs/#{command_event.id}/start", type: "result_bundle")

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert EnsureProjectPresencePlug.get_project(conn) == project
  end

  test "errors and halts the connection if the command event is not found" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> TuistWeb.Authentication.put_current_project(project)
      |> post(~p"/api/runs/8439289/start", type: "result_bundle")

    # Then
    assert conn.halted == true

    assert json_response(conn, :not_found) == %{
             "message" => "The command event 8439289 was not found."
           }
  end

  test "errors and halts the connection if the project is not found" do
    # Given
    opts = EnsureProjectPresencePlug.init([])
    conn = build_conn(:get, ~p"/api/cache", project_id: "non/existing")

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert conn.halted == true
    assert json_response(conn, 404) == %{"message" => "The project non/existing was not found."}
  end

  test "errors and halts the connection if the project id is invalid" do
    # Given
    opts = EnsureProjectPresencePlug.init([])
    conn = build_conn(:get, ~p"/api/cache", project_id: "only-project-name")

    # When
    conn = conn |> EnsureProjectPresencePlug.call(opts)

    # Then
    assert conn.halted == true

    assert json_response(conn, 401) == %{
             "message" =>
               "The project id \"only-project-name\" is missing either organization/user name or a project name. Make sure it's in the format of organization-name/project-name."
           }
  end
end
