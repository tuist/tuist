defmodule TuistWeb.LayoutLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic
  use Mimic

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.LayoutLive

  setup %{conn: conn} = context do
    conn = init_test_session(conn, %{})

    user = AccountsFixtures.user_fixture(preload: [:account])
    current_url = "https://test.tuist.io/path"

    stub(Phoenix.LiveView.Lifecycle, :attach_hook, fn _, _, _, func ->
      {:cont, socket} = func.(%{}, current_url, %LiveView.Socket{})
      socket
    end)

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        preload: [:account]
      )

    project =
      ProjectsFixtures.project_fixture(
        name: "tuist",
        account_id: account.id,
        visibility: :private,
        preload: [:account]
      )

    if role = Map.get(context, :user_role, nil) do
      Accounts.add_user_to_organization(user, organization, role: role)
    end

    conn = log_in_user(conn, user)
    session = get_session(conn)

    stub(Accounts, :avatar_color, fn _ -> "gray" end)

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
      assert_raise NotFoundError, fn ->
        live(conn, path)
      end
    end

    test "raises if the project doesn't exist", %{
      conn: conn,
      organization: organization
    } do
      # Given/When
      assert_raise NotFoundError, fn ->
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
               %{
                 label: organization.account.name,
                 icon: "smart_home",
                 avatar_color: "gray",
                 show_avatar: true,
                 items: [
                   %{
                     label: organization.account.name,
                     value: organization.account.id,
                     href: ~p"/#{organization.account.name}/projects",
                     selected: true,
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: user.account.name,
                     value: user.account.id,
                     href: ~p"/#{user.account.name}/projects",
                     selected: false,
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: "Create organization",
                     value: "create-organization",
                     href: ~p"/organizations/new",
                     selected: false,
                     icon: "building_plus"
                   }
                 ]
               },
               %{
                 items: [
                   %{
                     label: project.name,
                     value: project.id,
                     selected: true,
                     href: ~p"/#{organization.account.name}/#{project.name}",
                     badge: %{label: "Xcode", color: "focus"}
                   },
                   %{
                     label: "Create project",
                     value: "create-project",
                     href: ~p"/projects/new?account_id=#{organization.account.id}",
                     icon: "circle_plus",
                     selected: false
                   }
                 ],
                 label: project.name,
                 badge: %{label: "Xcode", color: "focus"}
               }
             ]

      assert socket.assigns.selected_project == project
      assert socket.assigns.selected_account.name == organization.account.name
      assert socket.assigns.selected_projects == [project]
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
                   %{
                     label: user.account.name,
                     selected: true,
                     href: ~p"/#{user.account.name}/projects",
                     value: user.account.id,
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: "Create organization",
                     value: "create-organization",
                     selected: false,
                     href: ~p"/organizations/new",
                     icon: "building_plus"
                   }
                 ],
                 label: user.account.name,
                 avatar_color: "gray",
                 show_avatar: true
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
                     label: organization.account.name,
                     value: organization.account.id,
                     selected: true,
                     href: ~p"/#{organization.account.name}/projects",
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: user.account.name,
                     value: user.account.id,
                     selected: false,
                     href: ~p"/#{user.account.name}/projects",
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: "Create organization",
                     value: "create-organization",
                     selected: false,
                     href: ~p"/organizations/new",
                     icon: "building_plus"
                   }
                 ],
                 label: organization.account.name,
                 avatar_color: "gray",
                 show_avatar: true
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
                     label: organization.account.name,
                     selected: true,
                     value: organization.account.id,
                     href: ~p"/#{organization.account.name}/projects",
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: user.account.name,
                     selected: false,
                     value: user.account.id,
                     href: ~p"/#{user.account.name}/projects",
                     avatar_color: "gray",
                     show_avatar: true
                   },
                   %{
                     label: "Create organization",
                     value: "create-organization",
                     selected: false,
                     href: ~p"/organizations/new",
                     icon: "building_plus"
                   }
                 ],
                 label: organization.account.name,
                 avatar_color: "gray",
                 show_avatar: true
               }
             ]

      assert socket.assigns.selected_account == organization.account
      assert socket.assigns.current_user_accounts == [organization.account, user.account]
      assert socket.assigns.can_read_billing == true
    end

    test "when the account is invalid", %{
      session: session
    } do
      assert_raise NotFoundError, fn ->
        LayoutLive.on_mount(
          :account,
          %{"account_handle" => "invalid"},
          session,
          %LiveView.Socket{}
        )
      end
    end
  end

  describe "SSO enforcement in on_mount/4 :account" do
    test "continues normally when org has SSO enforced and user has matching identity", %{
      session: session,
      user: user
    } do
      Accounts.link_oauth_identity_to_user(user, %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: "enforced.com"
      })

      %{account: enforced_account} =
        organization =
        AccountsFixtures.organization_fixture(
          name: "enforced-org",
          creator: user,
          sso_provider: :google,
          sso_organization_id: "enforced.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          %{"account_handle" => enforced_account.name},
          session,
          %LiveView.Socket{}
        )

      assert socket.assigns.selected_account == enforced_account
    end

    test "halts with redirect when org has SSO enforced and user has no matching identity", %{
      session: session,
      user: user
    } do
      %{account: enforced_account} =
        organization =
        AccountsFixtures.organization_fixture(
          name: "enforced-org-2",
          creator: user,
          sso_provider: :google,
          sso_organization_id: "enforced2.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      {:halt, socket} =
        LayoutLive.on_mount(
          :account,
          %{"account_handle" => enforced_account.name},
          session,
          %LiveView.Socket{}
        )

      assert socket.redirected ==
               {:redirect,
                %{
                  status: 302,
                  to: "/sso/verify?organization_id=#{organization.id}&return_to=%2F#{enforced_account.name}%2Fprojects"
                }}
    end

    test "continues normally when org has SSO but enforcement is disabled", %{
      session: session,
      user: user
    } do
      %{account: non_enforced_account} =
        AccountsFixtures.organization_fixture(
          name: "non-enforced-org",
          creator: user,
          sso_provider: :google,
          sso_organization_id: "notenforced.com",
          preload: [:account]
        )

      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          %{"account_handle" => non_enforced_account.name},
          session,
          %LiveView.Socket{}
        )

      assert socket.assigns.selected_account == non_enforced_account
    end

    test "continues normally for personal accounts (no organization)", %{
      session: session,
      user: user
    } do
      {:cont, socket} =
        LayoutLive.on_mount(
          :account,
          %{},
          session,
          %LiveView.Socket{}
        )

      assert socket.assigns.selected_account == user.account
    end
  end

  describe "SSO enforcement in on_mount/4 :project" do
    test "halts with redirect when project's org has SSO enforced and user has no matching identity",
         %{
           session: session,
           user: user,
           organization: organization,
           project: project
         } do
      Accounts.add_user_to_organization(user, organization, role: :user)

      Accounts.update_organization(organization, %{
        sso_provider: :google,
        sso_organization_id: "enforced-proj.com",
        sso_enforced: true
      })

      {:halt, socket} =
        LayoutLive.on_mount(
          :project,
          %{
            "account_handle" => organization.account.name,
            "project_handle" => project.name
          },
          session,
          %LiveView.Socket{}
        )

      assert socket.redirected ==
               {:redirect,
                %{
                  status: 302,
                  to:
                    "/sso/verify?organization_id=#{organization.id}&return_to=%2F#{organization.account.name}%2Fprojects"
                }}
    end

    @tag user_role: :user
    test "continues normally when project's org has SSO enforced and user has matching identity",
         %{
           params: params,
           session: session,
           user: user,
           organization: organization,
           project: project
         } do
      Accounts.link_oauth_identity_to_user(user, %{
        provider: :google,
        id_in_provider: "google-uid-#{System.unique_integer([:positive])}",
        provider_organization_id: "proj-enforced.com"
      })

      Accounts.update_organization(organization, %{
        sso_provider: :google,
        sso_organization_id: "proj-enforced.com",
        sso_enforced: true
      })

      {:cont, socket} =
        LayoutLive.on_mount(
          :project,
          params,
          session,
          %LiveView.Socket{}
        )

      assert socket.assigns.selected_project == project
    end
  end
end
