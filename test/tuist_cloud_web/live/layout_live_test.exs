defmodule TuistCloudWeb.LayoutLiveTest do
  use TuistCloudWeb.ConnCase, async: true

  alias TuistCloud.ProjectsFixtures
  alias TuistCloudWeb.LayoutLive
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  alias Phoenix.LiveView
  use Mimic
  import Phoenix.LiveViewTest

  setup %{conn: conn} = context do
    conn =
      conn
      |> init_test_session(%{})

    user = AccountsFixtures.user_fixture(preloads: [:account])
    current_url = "https://test.tuist.io/path"

    TuistCloud.Github
    |> stub(:get_most_recent_cli_release, fn ->
      nil
    end)

    Phoenix.LiveView.Lifecycle
    |> stub(:attach_hook, fn _, _, _, func ->
      {:cont, socket} = func.(%{}, current_url, %LiveView.Socket{})
      socket
    end)

    TuistCloud.Environment |> stub(:new_pricing_model?, fn -> true end)

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        preloads: [:account]
      )

    project =
      ProjectsFixtures.project_fixture(
        name: "tuist",
        account_id: account.id,
        visibility: :private,
        preloads: [:account]
      )

    if role = Map.get(context, :user_role, nil) do
      Accounts.add_user_to_organization(user, organization, role: role)
    end

    conn = conn |> log_in_user(user)
    session = conn |> get_session()

    %{
      conn: conn,
      session: session,
      organization: organization,
      project: project,
      user: user,
      params: %{
        "account_handle" => account.name,
        "project_handle" => project.name
      }
    }
  end

  describe "on_mount/4 when :project" do
    setup %{organization: organization, project: project} do
      %{path: ~p"/#{organization.account.name}/#{project.name}"}
    end

    test "raises if the current user is not authorized", %{
      conn: conn,
      path: path
    } do
      # Given/When
      assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
        live(conn, path)
      end
    end

    test "raises if the project doesn't exist", %{
      conn: conn,
      organization: organization
    } do
      # Given/When
      assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/invalid")
      end
    end

    @tag user_role: :user
    test "assigns the right values to the socket", %{
      params: params,
      session: session,
      user: user,
      organization: organization,
      project: project
    } do
      # Given/When
      {:cont, socket} =
        LayoutLive.on_mount(
          :project,
          params,
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.current_user == user

      assert socket.assigns.breadcrumbs == [
               %{content: organization.account.name},
               %{
                 items: [
                   %{
                     content: project.name,
                     href: ~p"/#{organization.account.name}/#{project.name}"
                   }
                 ],
                 content: project.name
               }
             ]

      assert socket.assigns.selected_project == project
      assert socket.assigns.selected_account.name == organization.account.name
      assert socket.assigns.selected_account_projects == [project]
    end
  end

  describe "on_mount/4 when :account" do
    test "assigns the right values when no account is passed", %{
      session: session,
      user: user
    } do
      # Given/When
      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          %{},
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.current_user == user

      assert socket.assigns.breadcrumbs == [
               %{
                 items: [
                   %{content: user.account.name, href: ~p"/#{user.account.name}/projects"}
                 ],
                 content: user.account.name
               }
             ]

      assert socket.assigns.selected_account == user.account
      assert socket.assigns.current_user_accounts == [user.account]
      assert socket.assigns.can_read_billing == true
    end

    @tag user_role: :user
    test "assigns the right values when current_user is user of the organization", %{
      params: params,
      session: session,
      user: user,
      organization: organization
    } do
      # Given/When
      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          params,
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.current_user == user

      assert socket.assigns.breadcrumbs == [
               %{
                 items: [
                   %{
                     content: organization.account.name,
                     href: ~p"/#{organization.account.name}/projects"
                   },
                   %{
                     content: user.account.name,
                     href: ~p"/#{user.account.name}/projects"
                   }
                 ],
                 content: organization.account.name
               }
             ]

      assert socket.assigns.selected_account == organization.account
      assert socket.assigns.current_user_accounts == [organization.account, user.account]
      assert socket.assigns.can_read_billing == false
    end

    @tag user_role: :admin
    test "assigns the right values when current_user has is admin of the organization", %{
      params: params,
      session: session,
      user: user,
      organization: organization
    } do
      # Given/When
      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          params,
          session,
          %LiveView.Socket{}
        )

      # Then
      assert socket.assigns.current_user == user

      assert socket.assigns.breadcrumbs == [
               %{
                 items: [
                   %{
                     content: organization.account.name,
                     href: ~p"/#{organization.account.name}/projects"
                   },
                   %{
                     content: user.account.name,
                     href: ~p"/#{user.account.name}/projects"
                   }
                 ],
                 content: organization.account.name
               }
             ]

      assert socket.assigns.selected_account == organization.account
      assert socket.assigns.current_user_accounts == [organization.account, user.account]
      assert socket.assigns.can_read_billing == true
    end

    test "when the account is invalid", %{
      session: session
    } do
      assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
        LayoutLive.on_mount(
          :account,
          %{"account_handle" => "invalid"},
          session,
          %LiveView.Socket{}
        )
      end
    end
  end
end
