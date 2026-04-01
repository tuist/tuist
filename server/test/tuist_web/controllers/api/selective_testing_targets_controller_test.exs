defmodule TuistWeb.API.SelectiveTestingTargetsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.CommandEvents
  alias Tuist.Tests
  alias Tuist.Xcode
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id/targets" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no targets", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)
      stub(CommandEvents, :get_command_event_by_test_run_id, fn _id -> {:ok, %{id: UUIDv7.generate()}} end)

      stub(Xcode, :selective_testing_analytics, fn _run, _flop_params ->
        {%{test_modules: []},
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets")

      assert %{
               "targets" => [],
               "pagination_metadata" => %{
                 "has_next_page" => false,
                 "has_previous_page" => false,
                 "current_page" => 1,
                 "page_size" => 20,
                 "total_count" => 0,
                 "total_pages" => 0
               }
             } = json_response(conn, 200)
    end

    test "returns targets with selective testing data", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)
      stub(CommandEvents, :get_command_event_by_test_run_id, fn _id -> {:ok, %{id: UUIDv7.generate()}} end)

      stub(Xcode, :selective_testing_analytics, fn _run, _flop_params ->
        {%{
           test_modules: [
             %{name: "AuthTests", selective_testing_hit: :miss, selective_testing_hash: "abc123"},
             %{name: "CoreTests", selective_testing_hit: :local, selective_testing_hash: "def456"},
             %{name: "UITests", selective_testing_hit: :remote, selective_testing_hash: "ghi789"}
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 3,
           total_pages: 1
         }}
      end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets")

      response = json_response(conn, 200)
      assert length(response["targets"]) == 3

      auth = Enum.find(response["targets"], &(&1["name"] == "AuthTests"))
      assert auth["hit_status"] == "miss"
      assert auth["hash"] == "abc123"

      core = Enum.find(response["targets"], &(&1["name"] == "CoreTests"))
      assert core["hit_status"] == "local"
      assert core["hash"] == "def456"

      ui = Enum.find(response["targets"], &(&1["name"] == "UITests"))
      assert ui["hit_status"] == "remote"
      assert ui["hash"] == "ghi789"
    end

    test "filters targets by hit_status", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)
      stub(CommandEvents, :get_command_event_by_test_run_id, fn _id -> {:ok, %{id: UUIDv7.generate()}} end)

      expect(Xcode, :selective_testing_analytics, fn _run, flop_params ->
        assert %{field: :selective_testing_hit, op: :==, value: "miss"} in flop_params.filters

        {%{
           test_modules: [
             %{name: "AuthTests", selective_testing_hit: :miss, selective_testing_hash: "abc123"}
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets?hit_status=miss"
        )

      response = json_response(conn, 200)
      assert length(response["targets"]) == 1
      assert hd(response["targets"])["hit_status"] == "miss"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)
      stub(CommandEvents, :get_command_event_by_test_run_id, fn _id -> {:ok, %{id: UUIDv7.generate()}} end)

      expect(Xcode, :selective_testing_analytics, fn _run, flop_params ->
        assert flop_params.page == 2
        assert flop_params.page_size == 10

        {%{
           test_modules: [
             %{name: "AuthTests", selective_testing_hit: :miss, selective_testing_hash: "abc123"}
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 10,
           total_count: 11,
           total_pages: 2
         }}
      end)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets?page=2&page_size=10"
        )

      response = json_response(conn, 200)
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "looks up the command event by test_run_id and passes it to selective_testing_analytics",
         %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)
      command_event_id = UUIDv7.generate()

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)

      expect(CommandEvents, :get_command_event_by_test_run_id, fn id ->
        assert id == test_run.id
        {:ok, %{id: command_event_id, created_at: NaiveDateTime.utc_now(), project_id: project.id}}
      end)

      expect(Xcode, :selective_testing_analytics, fn run, _flop_params ->
        assert run.id == command_event_id

        {%{test_modules: []},
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets")

      assert json_response(conn, 200)
    end

    test "returns 404 when command event is not found for test run",
         %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)

      stub(CommandEvents, :get_command_event_by_test_run_id, fn _id ->
        {:error, :not_found}
      end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets")

      assert %{"message" => _} = json_response(conn, 404)
    end

    test "returns 404 when test run is not found", %{conn: conn, user: user, project: project} do
      stub(Tests, :get_test, fn _id -> {:error, :not_found} end)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/tests/#{UUIDv7.generate()}/targets"
        )

      assert %{"message" => "Test run not found."} = json_response(conn, 404)
    end

    test "returns 404 when test run belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: other_project.id, account_id: user.account.id)

      stub(Tests, :get_test, fn _id -> {:ok, test_run} end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run.id}/targets")

      assert %{"message" => "Test run not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/tests/#{UUIDv7.generate()}/targets"
        )

      assert json_response(conn, :forbidden)
    end
  end
end
