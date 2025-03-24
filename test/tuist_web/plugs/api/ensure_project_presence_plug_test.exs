defmodule TuistWeb.API.EnsureProjectPresencePlugTest do
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  use TuistTestSupport.Cases.ConnCase, async: false
  use Plug.Test
  use Mimic
  alias TuistWeb.API.EnsureProjectPresencePlug

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  setup do
    cache = UUIDv7.generate() |> String.to_atom()
    {:ok, _} = Cachex.start_link(name: cache)
    {:ok, cache: cache}
  end

  test "caches fetching the project when caching is enabled", %{cache: cache} do
    # Given
    project = ProjectsFixtures.project_fixture(preload: [:account])
    account = Accounts.get_account_by_id(project.account_id)
    opts = EnsureProjectPresencePlug.init([])
    slug = account.name <> "/" <> project.name

    Tuist.Projects
    |> expect(:get_project_by_slug, 1, fn ^slug, _opts ->
      {:ok, project}
    end)

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> assign(:caching, true)
      |> assign(:cache, cache)
      |> assign(:cache_ttl, :timer.minutes(1))

    # When/Then
    for _n <- 0..10 do
      conn = conn |> EnsureProjectPresencePlug.call(opts)
      assert EnsureProjectPresencePlug.get_project(conn) == project
    end
  end

  test "loads and assigns the project to the connection if it exists" do
    # Given
    project = ProjectsFixtures.project_fixture(preload: [:account])
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
    project = ProjectsFixtures.project_fixture(preload: [:account])
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
