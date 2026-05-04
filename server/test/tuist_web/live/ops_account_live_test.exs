defmodule TuistWeb.OpsAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Kura
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    %{conn: conn, user: user}
  end

  test "renders account billing and Kura controls", %{conn: conn, user: user} do
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ user.account.name
    assert html =~ "Plan &amp; billing"
    assert html =~ "Kura"
    assert html =~ "Add Kura server"
  end

  test "one-click upgrade when the Stripe customer already has billing details", %{conn: conn, user: user} do
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

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "initiate_enterprise_upgrade", %{})
  end

  test "opens the enterprise form when the Stripe customer has no address", %{conn: conn, user: user} do
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok, %Stripe.Customer{name: "Acme", email: "acme@test", address: nil}}
    end)

    {:ok, lv, initial_html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    refute initial_html =~ "Upgrade #{user.account.name} to Enterprise"

    html = render_hook(lv, "initiate_enterprise_upgrade", %{})

    assert html =~ "Upgrade #{user.account.name} to Enterprise"
  end

  test "submits the enterprise form with the collected billing details", %{conn: conn, user: user} do
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

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "submit_enterprise_upgrade", %{
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
    subscription = BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

    expect(Billing, :cancel_subscription_at_period_end, fn sub ->
      assert sub.id == subscription.id
      {:ok, %{id: subscription.subscription_id, cancel_at_period_end: true}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "cancel_plan", %{})
  end
end
