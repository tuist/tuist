defmodule TuistWeb.AccountNotificationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.Notifications
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: log_in_user(conn, user), user: user}
  end

  defp register_device(user, name) do
    client = Clients.public!()
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user)
    token = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    {:ok, installation} =
      Push.register(user, session, Ecto.UUID.generate(), %{
        platform: "ios",
        token: token,
        environment: "production",
        name: name
      })

    installation
  end

  defp override(user, project) do
    Notifications.project_preference(user, "new_preview", project).override
  end

  test "shows the projects inline when only one account has projects", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
    shop = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "ios-shop")
    admin = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "android-admin")

    {:ok, lv, html} = live(conn, ~p"/#{user.account.name}/settings/notifications")
    # The personal account has no projects, so it isn't listed.
    assert html =~ "All projects in #{organization.account.name}"
    refute has_element?(lv, "#new-previews-account-edit-#{organization.account.id}")
    assert has_element?(lv, "#new-previews-project-#{shop.id}[data-enabled=true]")

    # A project switch that differs from All projects overrides it...
    render_hook(lv, "toggle_project:#{organization.account.id}:#{shop.id}", %{"checked" => false})
    assert override(user, shop) == false
    assert has_element?(lv, "#new-previews-project-#{shop.id}[data-enabled=false]")

    # ...and turning All projects off moves the projects that follow it, but not the override.
    render_hook(lv, "toggle_account:#{organization.account.id}", %{"checked" => false})
    assert has_element?(lv, "#new-previews-project-#{admin.id}[data-enabled=false]")
    refute Notifications.notify?(user.id, "new_preview", admin.id)

    # Matching All projects again follows the account instead of keeping an override.
    render_hook(lv, "toggle_project:#{organization.account.id}:#{shop.id}", %{"checked" => false})
    assert is_nil(override(user, shop))

    render_hook(lv, "toggle_project:#{organization.account.id}:#{admin.id}", %{"checked" => true})
    assert override(user, admin) == true
    assert Notifications.notify?(user.id, "new_preview", admin.id)
  end

  test "summarizes each account when several have projects and opens one to edit it", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
    shop = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "ios-shop")
    _admin = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "android-admin")
    personal = ProjectsFixtures.project_fixture(account_id: user.account.id, name: "side-project")
    :ok = Notifications.update_project_preference(user, "new_preview", shop.id, false)
    :ok = Notifications.update_account_preference(user, "new_preview", user.account.id, false)

    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings/notifications")
    assert has_element?(lv, "#new-previews-account-summary-#{organization.account.id}", "Custom")
    assert has_element?(lv, "#new-previews-account-summary-#{user.account.id}", "Off")
    refute has_element?(lv, "#new-previews-project-#{shop.id}")

    lv |> element("#new-previews-account-edit-#{organization.account.id}") |> render_click()
    assert has_element?(lv, "#new-previews-project-#{shop.id}[data-enabled=false]")
    refute has_element?(lv, "#new-previews-project-#{personal.id}")

    render_hook(lv, "toggle_project:#{organization.account.id}:#{shop.id}", %{"checked" => true})
    assert has_element?(lv, "#new-previews-account-summary-#{organization.account.id}", "On")
    assert is_nil(override(user, shop))
  end

  test "lists and removes devices", %{conn: conn, user: user} do
    installation = register_device(user, "iPhone 17 Pro")

    {:ok, lv, html} = live(conn, ~p"/#{user.account.name}/settings/notifications")
    assert html =~ "iPhone 17 Pro"

    lv |> element("#remove-device-#{installation.id}") |> render_click()

    refute render(lv) =~ "iPhone 17 Pro"
    assert Push.live_installations(user.id) == []
  end

  test "is only available on the user's own account", %{conn: conn, user: user} do
    %{account: organization} = AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{organization.name}/settings/notifications")
    end

    {:ok, _lv, html} = live(conn, ~p"/#{organization.name}/settings")
    refute html =~ "/#{organization.name}/settings/notifications"
  end
end
