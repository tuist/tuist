defmodule TuistWeb.RunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "download/2" do
    test "redirects to the result bundle download url when user has permission", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      stub(Storage, :generate_download_url, fn _object_key, _actor -> "https://tuist.io" end)

      # When
      conn =
        get(conn, ~p"/#{user.account.name}/#{project.name}/runs/#{command_event.id}/download")

      # Then
      assert redirected_to(conn) == "https://tuist.io"
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
