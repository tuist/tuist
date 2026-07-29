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

  test "renders the Kura cache servers and cache endpoints sections when available", %{
    conn: conn,
    account: account
  } do
    # Given
    stub(FunWithFlags, :enabled?, fn
      :kura, _ -> true
      _, _ -> false
    end)

    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :get_current_active_subscription, fn _ -> %{plan: :enterprise} end)

    # When
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    # Then
    assert html =~ "Kura cache servers"
    assert html =~ "Cache endpoints"
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
