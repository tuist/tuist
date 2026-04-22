defmodule TuistWeb.OpsAccountsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Billing
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

  test "one-click upgrade when the Stripe customer already has billing details", %{conn: conn, user: user} do
    # Given — the customer already has name/email/address on Stripe, so ops
    # shouldn't have to re-enter them.
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok,
       %Stripe.Customer{
         name: "Acme",
         email: "billing@acme.test",
         address: %{
           line1: "1 Market St",
           city: "SF",
           postal_code: "94103",
           country: "US"
         }
       }}
    end)

    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params == %{cadence: "monthly"}
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts")

    # When/then — `expect/2` + `verify_on_exit!` (in setup) asserts
    # upgrade_to_enterprise was called once with just the cadence (no modal).
    render_hook(lv, "initiate_enterprise_upgrade", %{"id" => to_string(user.account.id)})
  end

  test "opens the enterprise form when the Stripe customer has no address", %{conn: conn, user: user} do
    # Given — Stripe customer is missing address, so the modal must open.
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok, %Stripe.Customer{name: "Acme", email: "acme@test", address: nil}}
    end)

    {:ok, lv, initial_html} = live(conn, ~p"/ops/accounts")

    # The shared modal isn't in the DOM until ops opens it for an account.
    refute initial_html =~ "Upgrade #{user.account.name} to Enterprise"

    # When — an initiate without ready billing details sets the assign and
    # pushes `open-modal` so the modal renders for this account.
    html = render_hook(lv, "initiate_enterprise_upgrade", %{"id" => to_string(user.account.id)})

    # Then — the modal is now rendered, populated with the account's name.
    assert html =~ "Upgrade #{user.account.name} to Enterprise"
  end

  test "submits the enterprise form with the collected billing details", %{conn: conn, user: user} do
    # Given
    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params.name == "Acme Corp"
      assert params.billing_email == "billing@acme.test"
      assert params.cadence == "yearly"
      assert params.address.line1 == "1 Market St"
      assert params.address.city == "San Francisco"
      assert params.address.postal_code == "94103"
      assert params.address.country == "US"
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts")

    # When/then — dispatch the submit event directly. The form lives inside
    # the modal's Noora <template> portal, which Floki selectors don't
    # traverse, so going through `form/3` + `render_submit/1` isn't an
    # option. The `account_id` hidden field wires the form to its target
    # account, so the modal doesn't have to be open for this to work.
    # `expect/2` + `verify_on_exit!` asserts upgrade_to_enterprise fired
    # with the right params.
    render_hook(lv, "submit_enterprise_upgrade", %{
      "account_id" => to_string(user.account.id),
      "name" => "Acme Corp",
      "billing_email" => "billing@acme.test",
      "address_line1" => "1 Market St",
      "address_line2" => "",
      "address_city" => "San Francisco",
      "address_state" => "CA",
      "address_postal_code" => "94103",
      "address_country" => "us",
      "cadence" => "yearly"
    })
  end

  test "Cancel plan cancels the active subscription at period end", %{conn: conn, user: user} do
    # Given
    subscription = BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

    expect(Billing, :cancel_subscription_at_period_end, fn sub ->
      assert sub.id == subscription.id
      {:ok, %{id: subscription.subscription_id, cancel_at_period_end: true}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts")

    # When/then — dispatch the dropdown event directly (the item lives
    # inside a <template> portal and isn't reachable via DOM selectors).
    # `expect/2` + `verify_on_exit!` asserts the cancel call fired.
    render_hook(lv, "cancel_plan", %{"id" => to_string(user.account.id)})
  end
end
