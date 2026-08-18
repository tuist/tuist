defmodule TuistWeb.BillingLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Billing
  alias Tuist.Runners.Prepaid
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} = context do
    user = AccountsFixtures.user_fixture()
    account_without_customer = Map.get(context, :account_without_customer, true)

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        customer_id: if(account_without_customer, do: "customer_id"),
        creator: user,
        preload: [:account],
        current_month_remote_cache_hits_count: 167
      )

    if account_without_customer do
      stub(Billing, :get_customer_by_id, fn _ ->
        %{
          id: UUIDv7.generate(),
          email: account.billing_email
        }
      end)
    end

    stub(Billing, :get_subscription_current_period_end, fn _ ->
      "UTC" |> DateTime.now!() |> DateTime.shift(day: 3)
    end)

    stub(Billing, :get_payment_method_by_id, fn _ ->
      %{
        id: "payment_method_id",
        card: %{
          brand: "visa",
          last4: "4242",
          exp_month: 1,
          exp_year: 2026
        }
      }
    end)

    stub(Prepaid, :balance, fn _account -> nil end)

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "sets the right title", %{conn: conn, account: account} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/billing")

    assert html =~ "Billing · #{account.name} · Tuist"
  end

  test "links to the Stripe customer portal to update billing details", %{conn: conn, account: account} do
    {:ok, live_view, _html} = live(conn, ~p"/#{account.name}/billing")

    assert has_element?(
             live_view,
             "[data-part='billing-details-card-section'] a[href='/#{account.name}/billing/manage']",
             "Update billing details"
           )

    assert has_element?(
             live_view,
             "[data-part='billing-details-card-section']",
             "Update the company name, billing address, tax number, and email shown on your invoices."
           )
  end

  describe "no active plan" do
    test "renders the correct information", %{conn: conn, account: account} do
      # When
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Then
      assert has_element?(lv, "[data-part='current-plan-card-section']", "Air")
      assert has_element?(lv, "[data-part='next-charge-date']", "charged /per month")
    end
  end

  describe "when air plan" do
    test "renders the correct information", %{conn: conn, account: account} do
      # Given
      stub(Billing, :get_current_active_subscription, fn _ ->
        %{
          plan: :air,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      stub(Billing, :get_subscription_current_period_end, fn _ ->
        ~U[2024-01-15 14:30:00Z]
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Then
      assert has_element?(lv, "[data-part='current-plan-card-section']", "Air")
      assert has_element?(lv, "[data-part='next-charge-date']", "charged on January 15")
    end
  end

  describe "when pro plan" do
    @tag account_without_customer: true
    test "renders the correct information when the customer id is present", %{
      conn: conn,
      account: account
    } do
      # Given
      stub(Billing, :get_current_active_subscription, fn _ ->
        %{
          plan: :pro,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Then
      assert has_element?(lv, "[data-part='current-plan-card-section']", "Air")
    end

    @tag account_without_customer: false
    test "renders the correct information when the customer id is not present", %{
      conn: conn,
      account: account
    } do
      # Given
      stub(Billing, :get_current_active_subscription, fn _ ->
        %{
          plan: :pro,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Then
      assert has_element?(lv, "[data-part='current-plan-card-section']", "Air")
    end
  end

  describe "when enterprise" do
    test "renders billing when a user has the enterprise plan", %{conn: conn, account: account} do
      # Given
      stub(Billing, :get_current_active_subscription, fn _ ->
        %{
          plan: :enterprise,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Then
      assert has_element?(lv, "[data-part='current-plan-card-section']", "Enterprise")
    end
  end

  describe "when payment method card is nil" do
    @tag account_without_customer: true
    test "does not crash when payment method has nil card", %{conn: conn, account: account} do
      # Given
      stub(Billing, :get_current_active_subscription, fn _ ->
        %{
          plan: :pro,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      stub(Billing, :get_payment_method_id_from_subscription_id, fn _ ->
        "payment_method_id"
      end)

      stub(Billing, :get_payment_method_by_id, fn _ ->
        %{
          id: "payment_method_id",
          card: nil
        }
      end)

      # When/Then
      assert {:ok, _lv, _html} = live(conn, ~p"/#{account.name}/billing")
    end
  end

  describe "prepaid runner credit" do
    test "is hidden for an account with no runner credit", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      refute has_element?(lv, "[data-part='prepaid-credit-card']")
    end

    test "shows what is left, and when each grant runs out", %{conn: conn, account: account} do
      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(650_000, :USD),
          expires_at: ~U[2026-09-01 00:00:00Z],
          grants: [
            %{
              id: "credgr_trial",
              kind: "trial",
              available: Money.new(250_000, :USD),
              expires_at: ~U[2026-09-01 00:00:00Z]
            },
            %{
              id: "credgr_prepaid",
              kind: "prepaid",
              available: Money.new(400_000, :USD),
              expires_at: ~U[2027-01-01 00:00:00Z]
            }
          ]
        }
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      assert has_element?(lv, "[data-part='prepaid-credit-card']", "Prepaid runner credit")
      assert has_element?(lv, "#prepaid-runner-credit-table", "Trial credit")
      assert has_element?(lv, "#prepaid-runner-credit-table", "Prepaid credit")
      assert has_element?(lv, "#prepaid-runner-credit-table", "September 1, 2026")
      assert has_element?(lv, "#prepaid-runner-credit-table", "January 1, 2027")
    end
  end
end
