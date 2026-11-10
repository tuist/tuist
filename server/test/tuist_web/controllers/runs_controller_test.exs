defmodule TuistWeb.RunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  describe "download/2" do
    test "redirects to the result bundle download url when user has permission", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      stub(Storage, :get_object_range, fn _object_key, 0..1, _actor -> {:ok, "pb"} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://tuist.io" end)

      # When
      conn =
        get(conn, ~p"/#{user.account.name}/#{project.name}/runs/#{command_event.id}/download")

      # Then
      assert redirected_to(conn) == "https://tuist.io"
    end

    test "canonical immutable routes download the original case-sensitive shard bundle", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 1, reporting_version: 1)
      source_id = String.upcase(UUIDv7.generate())
      stub(Tuist.Tasks, :run_async, fn _ -> :ok end)

      assert {:ok, _} =
               Tests.create_test(%{
                 id: plan.id,
                 source_test_run_id: source_id,
                 project_id: project.id,
                 account_id: user.account.id,
                 shard_plan_id: plan.id,
                 shard_index: 0,
                 status: "success",
                 duration: 1,
                 is_ci: true,
                 test_modules: []
               })

      key = "#{user.account.name}/#{project.name}/runs/#{source_id}/result_bundle.zip"
      stub(Storage, :object_exists?, fn object_key, _ -> object_key == key end)
      stub(Storage, :get_object_range, fn ^key, 0..1, _ -> {:ok, "PK"} end)
      expect(Storage, :generate_download_url, fn ^key, _, _ -> "https://tuist.io/shard-bundle" end)
      conn = get(conn, ~p"/#{user.account.name}/#{project.name}/runs/#{plan.id}/download")
      assert redirected_to(conn) == "https://tuist.io/shard-bundle"
    end

    test "legacy downloads preserve uppercase IDs supplied in the route", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      source_id = String.upcase(UUIDv7.generate())
      {:ok, _} = RunsFixtures.test_fixture(id: source_id, project_id: project.id)
      key = "#{user.account.name}/#{project.name}/runs/#{source_id}/result_bundle.zip"
      stub(Storage, :object_exists?, fn object_key, _ -> object_key == key end)
      stub(Storage, :get_object_range, fn ^key, 0..1, _ -> {:ok, "PK"} end)
      expect(Storage, :generate_download_url, fn ^key, _, _ -> "https://tuist.io/legacy-bundle" end)
      conn = get(conn, ~p"/#{user.account.name}/#{project.name}/runs/#{source_id}/download")
      assert redirected_to(conn) == "https://tuist.io/legacy-bundle"
    end

    test "returns 404 when command event does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = log_in_user(conn, user)
      non_existent_id = "00000000-0000-0000-0000-000000000000"
      # When
      conn =
        get(conn, ~p"/#{user.account.name}/#{project.name}/runs/#{non_existent_id}/download")

      # Then
      assert json_response(conn, 404)["message"] == "The resource could not be found."
    end

    test "returns 404 when user does not have permission", %{conn: conn} do
      # Given
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: owner.account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      conn = log_in_user(conn, other_user)

      # When
      # The require_user_can_read_project plug returns 404 for security reasons
      # (to not reveal existence of projects users don't have access to)
      assert_error_sent 404, fn ->
        get(conn, ~p"/#{owner.account.name}/#{project.name}/runs/#{command_event.id}/download")
      end
    end
  end
end
