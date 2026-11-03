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

  test "toggles new previews per account and lists project overrides with a reset", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
    shop = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "ios-shop")
    admin = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "android-admin")

    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings/notifications")
    refute has_element?(lv, "#new-previews-project-#{shop.id}")

    render_hook(lv, "toggle_account:#{organization.account.id}", %{"checked" => false})
    refute Notifications.notify?(user.id, "new_preview", admin.id)

    :ok = Notifications.update_project_preference(user, "new_preview", shop.id, true)
    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings/notifications")
    assert has_element?(lv, "#new-previews-project-#{shop.id}", "ios-shop on")
    refute has_element?(lv, "#new-previews-project-#{admin.id}")

    lv |> element("#new-previews-project-#{shop.id} [data-part=dismiss-icon]") |> render_click()
    refute has_element?(lv, "#new-previews-project-#{shop.id}")
    refute Notifications.notify?(user.id, "new_preview", shop.id)
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
