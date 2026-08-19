defmodule TuistWeb.OpsAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Kura
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Prepaid
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Accounts, :tuist_operator?, fn _ -> true end)
    # Default the balance away so no test in this file reaches Stripe on
    # mount. The balance itself is covered in Tuist.Runners.PrepaidTest.
    stub(Prepaid, :balance, fn _account -> nil end)

    %{conn: conn, user: user}
  end

  test "renders account billing controls", %{conn: conn, user: user} do
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ user.account.name
    assert html =~ "Plan &amp; billing"
    assert html =~ "Kura"
    assert html =~ "Runner concurrency"
    assert html =~ "value=\"12\""
  end

  test "updates platform-specific runner concurrency limits", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    lv
    |> form("#runner-concurrency-form", %{
      "account" => %{
        "runner_linux_vcpus_limit" => "48",
        "runner_linux_memory_gb_limit" => "96",
        "runner_macos_vcpus_limit" => "18",
        "runner_macos_memory_gb_limit" => "42"
      }
    })
    |> render_submit()

    assert Concurrency.limits_for(user.account, :linux) == %{vcpus: 48, memory_gb: 96}
    assert Concurrency.limits_for(user.account, :macos) == %{vcpus: 18, memory_gb: 42}
  end

  test "links Kura servers to their latest deployment", %{conn: conn, user: user} do
    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "0.5.2"
    refute html =~ "kura@0.5.2"
    assert html =~ ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}"
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

  describe "prepaid runner credit" do
    test "quotes the money as minutes are typed, before anything is charged", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      reject(&Prepaid.bill_prepaid_minutes/3)

      html =
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
        |> render_change()

      assert html =~ "600.00"
      assert html =~ "750.00"
    end

    test "adds the charge to the next invoice rather than granting credit now", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      expect(Prepaid, :bill_prepaid_minutes, fn account, minutes ->
        assert account.id == user.account.id
        assert minutes == 10_000
        {:ok, %{id: "ii_1"}}
      end)

      # `expect` above is the assertion: it pins the account and the
      # minute count, and verify_on_exit! fails the test if the charge
      # was never created.
      lv
      |> form("#prepaid-minutes-form", %{"minutes" => "10000"})
      |> render_submit()
    end

    test "refuses a minute count that is not a positive whole number", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      reject(&Prepaid.bill_prepaid_minutes/3)

      # `reject` is the assertion: nothing may reach Stripe for any of
      # these, so no charge is created from a malformed minute count.
      for value <- ["0", "-5", "abc", "1.5", ""] do
        lv
        |> form("#prepaid-minutes-form", %{"minutes" => value})
        |> render_submit()
      end
    end

    test "warns when the account has no subscription to bill against", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert has_element?(lv, "#prepaid-no-subscription-alert")
    end

    test "lists the credit the account already holds", %{conn: conn, user: user} do
      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(75_000, :USD),
          expires_at: ~U[2027-01-01 00:00:00Z],
          grants: [
            %{
              id: "credgr_1",
              kind: "prepaid",
              available: Money.new(75_000, :USD),
              expires_at: ~U[2027-01-01 00:00:00Z]
            }
          ]
        }
      end)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert has_element?(lv, "#prepaid-balance-table", "Prepaid credit")
      assert has_element?(lv, "#prepaid-balance-table", "January 1, 2027")
    end
  end
end
