defmodule TuistCloudWeb.AppTest do
  use TuistCloudWeb.ConnCase, async: true

  alias TuistCloud.ProjectsFixtures
  alias TuistCloudWeb.Authentication
  alias TuistCloudWeb.App
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  alias Phoenix.LiveView

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})

    user = AccountsFixtures.user_fixture()

    user_token = Accounts.generate_user_session_token(user)
    organization = AccountsFixtures.organization_fixture(name: "tuist-org", creator: user)
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)
    organization_two = AccountsFixtures.organization_fixture(name: "tuist-org-2")
    Accounts.add_user_to_organization(user, organization_two)
    account_two = Accounts.get_account_from_organization(organization_two)
    ProjectsFixtures.project_fixture(name: "tuist-2", account_id: account_two.id)

    session =
      conn
      |> Authentication.log_in_user(user)
      |> get_session()
      |> Map.put(:user_token, user_token)

    %{conn: conn, session: session, project: project, user: user}
  end

  describe "on_mount/4" do
    test "assigns current owner", %{session: session} do
      # When
      {:cont, socket} =
        App.on_mount(
          :mount_app,
          %{
            "owner" => "tuist-org",
            "project" => "tuist"
          },
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.selected_owner == "tuist-org"
    end

    test "assigns current project", %{session: session, project: project} do
      # When
      {:cont, socket} =
        App.on_mount(
          :mount_app,
          %{
            "owner" => "tuist-org",
            "project" => "tuist"
          },
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.selected_project == project
    end

    test "assigns current user", %{session: session, user: user} do
      # When
      {:cont, socket} =
        App.on_mount(
          :mount_app,
          %{
            "owner" => "tuist-org",
            "project" => "tuist"
          },
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.current_user == user
    end

    test "assigns current account", %{session: session, user: user} do
      # When
      {:cont, socket} =
        App.on_mount(
          :mount_app,
          %{
            "owner" => "tuist-org",
            "project" => "tuist"
          },
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.selected_account == Accounts.get_account_from_user(user)
    end

    test "assigns projects", %{session: session} do
      # When
      {:cont, socket} =
        App.on_mount(
          :mount_app,
          %{
            "owner" => "tuist-org",
            "project" => "tuist"
          },
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.projects |> Enum.map(& &1.project.name) |> Enum.sort() == [
               "tuist",
               "tuist-2"
             ]
    end
  end

  test "assigns can_update_billing to true when a user is an admin of an organization", %{
    session: session
  } do
    # When
    {:cont, socket} =
      App.on_mount(
        :mount_app,
        %{
          "owner" => "tuist-org",
          "project" => "tuist"
        },
        session,
        %LiveView.Socket{}
      )

    # Then
    assert socket.assigns.can_update_billing == true
  end

  test "assigns can_update_billing to false when a user is only a member of an organization", %{
    session: session
  } do
    # When
    {:cont, socket} =
      App.on_mount(
        :mount_app,
        %{
          "owner" => "tuist-org-2",
          "project" => "tuist-2"
        },
        session,
        %LiveView.Socket{}
      )

    # Then
    assert socket.assigns.can_update_billing == false
  end

  test "raises NotFoundError when a project does not exist", %{session: session} do
    # When / Then
    assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
      App.on_mount(
        :mount_app,
        %{
          "owner" => "tuist-org",
          "project" => "non-existent"
        },
        session,
        %LiveView.Socket{}
      )
    end
  end
end
