defmodule TuistWeb.RunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Errors.UnauthorizedError
  alias TuistWeb.RunsController

  describe "download/2" do
    test "redirects to the result bundle download url when user has permission", %{conn: conn} do
      # Given
      user = Repo.preload(AccountsFixtures.user_fixture(), :account)

      conn = assign(conn, :current_user, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      stub(Storage, :generate_download_url, fn _ -> "https://tuist.io" end)

      # When
      conn =
        RunsController.download(conn, %{
          "id" => command_event.id
        })

      # Then
      assert redirected_to(conn) == "https://tuist.io"
    end

    test "raised NotFoundError when command event does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = assign(conn, :current_user, user)

      # When

      assert_raise NotFoundError, fn ->
        RunsController.download(conn, %{
          "id" => unique_integer()
        })
      end
    end

    test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = assign(conn, :current_user, user)
      command_event = CommandEventsFixtures.command_event_fixture()

      # When
      assert_raise UnauthorizedError, fn ->
        RunsController.download(conn, %{
          "id" => command_event.id
        })
      end
    end
  end
end
