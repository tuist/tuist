defmodule TuistCloudWeb.RunsControllerTest do
  use TuistCloudWeb.ConnCase, async: true

  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Repo
  alias TuistCloud.Storage
  alias TuistCloudWeb.Errors.UnauthorizedError
  alias TuistCloud.TestUtilities
  alias TuistCloudWeb.Errors.NotFoundError
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloudWeb.RunsController
  use Mimic

  describe "download/2" do
    test "redirects to the result bundle download url when user has permission", %{conn: conn} do
      # Given
      user =
        AccountsFixtures.user_fixture()
        |> Repo.preload(:account)

      conn = conn |> assign(:current_user, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      command_event = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      Storage
      |> stub(:generate_download_url, fn _ -> "https://tuist.io" end)

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
      conn = conn |> assign(:current_user, user)

      # When

      assert_raise NotFoundError, fn ->
        RunsController.download(conn, %{
          "id" => TestUtilities.unique_integer()
        })
      end
    end

    test "raises UnauthorizedError when user does not have permission", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = conn |> assign(:current_user, user)
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
