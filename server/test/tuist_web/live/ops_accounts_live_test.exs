defmodule TuistWeb.OpsAccountsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    Mimic.stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    %{conn: conn, user: user}
  end

  test "lists accounts with their plan", %{conn: conn, user: user} do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "acme")
    org_account = Accounts.get_account_from_organization(organization)
    _subscription = BillingFixtures.subscription_fixture(account_id: org_account.id, plan: :pro)

    # When
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts")

    # Then
    assert html =~ "Accounts"
    assert html =~ user.account.name
    assert html =~ "acme"
    assert html =~ "Pro"
    assert html =~ "Air"
    assert html =~ "Active"
  end

  test "flags the Cancelled status when cancel_at_period_end is set", %{conn: conn} do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "acme")
    org_account = Accounts.get_account_from_organization(organization)

    subscription =
      BillingFixtures.subscription_fixture(account_id: org_account.id, plan: :pro)

    # Simulate the webhook sync: cancel_at_period_end flipped but status
    # still "active" until the period actually ends.
    Tuist.Repo.update!(Ecto.Changeset.change(subscription, cancel_at_period_end: true))

    # When
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts")

    # Then
    assert html =~ "Cancelled"
  end

  test "paginates when there are more accounts than one page", %{conn: conn} do
    # Given — 31 organizations put us past the 30-per-page default.
    for i <- 1..31, do: AccountsFixtures.organization_fixture(name: "pagtestorg#{i}")

    # When
    {:ok, lv, html} = live(conn, ~p"/ops/accounts")

    # Then — pagination control is rendered with a link to page 2.
    assert html =~ "noora-pagination-group"
    assert html =~ "page=2"

    # Navigating to page 2 via the numbered pagination button re-renders.
    page2_html =
      lv
      |> element(~s(a[href*="page=2"][data-part="page-button"]))
      |> render_click()

    assert page2_html =~ "noora-pagination-group"
  end

  test "filters accounts by handle", %{conn: conn, user: user} do
    # Given
    _organization = AccountsFixtures.organization_fixture(name: "uniquetestorg")

    # When
    {:ok, lv, initial_html} = live(conn, ~p"/ops/accounts")

    # Verify both accounts initially appear in the table
    assert initial_html =~ ~s(id="ops-accounts-table")
    assert initial_html =~ user.account.name
    assert initial_html =~ "uniquetestorg"

    html =
      lv
      |> form("form[phx-submit=\"search\"]", %{search: "uniquetestorg"})
      |> render_change()

    # Then — the filtered account still appears, the user handle only shows
    # in the account dropdown header (which is always present). Verify the
    # user handle is no longer in a table row.
    assert html =~ "uniquetestorg"
    table_row = html |> Floki.parse_fragment!() |> Floki.find("#ops-accounts-table tbody tr")
    table_html = Floki.raw_html(table_row)
    refute table_html =~ user.account.name
  end
end
