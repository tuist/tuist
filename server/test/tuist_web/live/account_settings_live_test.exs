defmodule TuistWeb.AccountSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-org",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "sets the right title", %{conn: conn, account: account} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Settings · #{account.name} · Tuist"
  end

  test "personal settings expose independent passkey and authenticator management", %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/#{user.account.name}/settings")

    assert has_element?(view, "#passkeys-settings a[href='/users/settings/passkeys']", "Manage passkeys")
    assert has_element?(view, "#passkeys-settings", "0 passkeys added")
    assert has_element?(view, "#two-factor-settings a[href='/users/settings/mfa']", "Manage two-factor authentication")
    assert has_element?(view, "#two-factor-settings", "Not enabled")
    refute has_element?(view, "#two-factor-settings", "passkeys")

    stub(Environment, :email_auth_enabled?, fn -> false end)
    {:ok, view, _html} = live(conn, ~p"/#{user.account.name}/settings")
    refute has_element?(view, "#passkeys-settings")
    assert has_element?(view, "#two-factor-settings")
  end

  test "renders cache endpoints but no managed cache section", %{
    conn: conn,
    account: account
  } do
    # Given
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :get_current_active_subscription, fn _ -> %{plan: :enterprise} end)

    # When
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    # Then
    assert html =~ "Cache endpoints"
    refute html =~ "Manage passkeys"
    refute html =~ "Manage two-factor authentication"
    # Where an account's cache runs is neither asked of it nor reported to it.
    refute html =~ "Managed cache"
    refute html =~ "Deploy Kura server"
    refute html =~ "create_kura_server"
    refute html =~ "destroy_kura_server"
  end

  test "raises UnauthorizedError when the user is not authorized to update settings", %{
    conn: conn
  } do
    # Given
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    user = AccountsFixtures.user_fixture()

    Accounts.add_user_to_organization(user, organization)

    conn = log_in_user(conn, user)

    # When / Then
    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/settings")
    end
  end

  test "allows an operator holding an admin grant to access settings for any account", %{
    conn: conn
  } do
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    stub(Environment, :tuist_hosted?, fn -> true end)
    user = AccountsFixtures.user_fixture(email: "operator-#{System.unique_integer([:positive])}@tuist.dev")
    AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google)
    now = System.system_time(:second)

    conn =
      conn
      |> log_in_user(user)
      |> Plug.Conn.put_session("operator_grants", %{
        organization.account.name => %{
          tier: :admin,
          account_id: organization.account.id,
          account_handle: organization.account.name,
          sub: user.email,
          reason: "support",
          jti: "1",
          iat: now,
          exp: now + 600
        }
      })

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings")

    assert html =~ "Settings · #{organization.account.name} · Tuist"
  end

  test "displays the 'Rename organization' button when the selected account is an organization",
       %{
         conn: conn,
         account: account
       } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Rename organization")
  end

  test "displays the 'Update username' button when the selected account is a user account",
       %{
         conn: conn,
         user: user
       } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Update username")
  end
end
