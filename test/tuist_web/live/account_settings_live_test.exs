defmodule TuistWeb.AccountSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)

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
    {:ok, _lv, html} =
      conn
      |> live(~p"/noora/#{account.name}/settings")

    assert html =~ "Settings · #{account.name} · Tuist"
  end

  test "raises UnauthorizedError when the user is not authorized to update settings", %{
    conn: conn
  } do
    # Given
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    user = AccountsFixtures.user_fixture()

    Accounts.add_user_to_organization(user, organization)

    conn =
      conn
      |> log_in_user(user)

    # When / Then
    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      conn
      |> live(~p"/noora/#{organization.account.name}/settings")
    end
  end

  test "displays the 'Rename organization' button when the selected account is an organization",
       %{
         conn: conn,
         account: account
       } do
    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Rename organization")
  end

  test "displays the 'Update username' button when the selected account is a user account",
       %{
         conn: conn,
         user: user
       } do
    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{user.account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Update username")
  end
end
