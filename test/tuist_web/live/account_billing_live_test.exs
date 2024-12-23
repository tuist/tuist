defmodule TuistWeb.AccountBillingLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  alias Tuist.Billing
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        customer_id: "customer_id",
        creator: user,
        preload: [:account],
        current_month_remote_cache_hits_count: 167
      )

    Billing
    |> stub(:get_customer_by_id, fn _ ->
      %{
        id: "customer_id",
        email: "customer_email"
      }
    end)

    Billing
    |> stub(:get_subscription_current_period_end, fn _ ->
      DateTime.now!("UTC") |> DateTime.shift(day: 3)
    end)

    Billing
    |> stub(:get_payment_method_by_id, fn _ ->
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

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user}
  end

  test "sets the right title", %{conn: conn} do
    # When
    {:ok, _lv, html} =
      conn
      |> live(~p"/tuist-org/billing")

    assert html =~ "Billing · tuist-org · Tuist"
  end

  test "raises UnauthorizedError when the user is not authorized to update billing", %{
    conn: conn,
    user: user
  } do
    # Given
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    Accounts.add_user_to_organization(user, organization)

    # When / Then
    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/billing")
    end
  end

  test "raises NotFoundError when the plan is invalid", %{conn: conn, user: user} do
    # Given
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/billing?new_plan=invalid")
    end
  end

  describe "no active plan" do
    test "renders the correct information", %{conn: conn} do
      # When
      {:ok, lv, _html} =
        conn
        |> live(~p"/tuist-org/billing")

      # Then
      assert has_element?(lv, ".billing__overview__plan-card", "Air plan")
      refute has_element?(lv, "billing__pricing__plans button > button", "Current plan")
      refute has_element?(lv, "billing__pricing__plans button > button", "Upgrade")
      refute has_element?(lv, "billing__pricing__plans button > button", "Contact sales")
    end
  end

  describe "when air plan" do
    test "renders the correct information", %{conn: conn} do
      # Given
      Billing
      |> stub(:get_current_active_subscription, fn _ ->
        %{
          plan: :air,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} =
        conn
        |> live(~p"/tuist-org/billing")

      # Then
      assert has_element?(lv, ".billing__overview__plan-card__plan-summary__info", "Air plan")
      refute has_element?(lv, "button", "Downgrade")
      assert has_element?(lv, "button", "Upgrade")
      assert has_element?(lv, "button", "Current plan")
      assert has_element?(lv, "p", "167 of 200 remote cache hits")
    end
  end

  describe "when pro plan" do
    test "renders the correct information", %{conn: conn} do
      # Given
      Billing
      |> stub(:get_current_active_subscription, fn _ ->
        %{
          plan: :pro,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} =
        conn
        |> live(~p"/tuist-org/billing")

      # Then
      assert has_element?(lv, ".billing__overview__plan-card__plan-summary__info", "Pro plan")
      assert has_element?(lv, "button", "Downgrade")
      refute has_element?(lv, "button", "Upgrade")
      assert has_element?(lv, "button", "Current plan")
      assert has_element?(lv, "p", "167 of 200 free remote cache hits")
    end
  end

  describe "when enterprise" do
    test "renders billing when a user has the enterprise plan", %{conn: conn} do
      # Given
      Billing
      |> stub(:get_current_active_subscription, fn _ ->
        %{
          plan: :enterprise,
          status: "active",
          default_payment_method: "payment_method_id",
          trial_end: nil,
          subscription_id: "subscription_id"
        }
      end)

      # When
      {:ok, lv, _html} =
        conn
        |> live(~p"/tuist-org/billing")

      # Then
      assert has_element?(
               lv,
               ".billing__overview__plan-card__plan-summary__info",
               "Enterprise plan"
             )

      assert has_element?(lv, "p", "Enterprise plan")
      assert has_element?(lv, "h3", "Custom")
      refute has_element?(lv, "button", "Downgrade")
      refute has_element?(lv, "button", "Upgrade")
    end
  end
end
