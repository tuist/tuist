defmodule TuistCloudWeb.BillingLiveTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  alias TuistCloud.Environment
  alias TuistCloud.Billing
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures

  setup %{conn: conn} do
    Billing
    |> stub(:start_trial, fn _ -> {:ok, %{}} end)

    Environment
    |> stub(:new_pricing_model?, fn -> true end)

    user = AccountsFixtures.user_fixture()

    AccountsFixtures.organization_fixture(
      name: "tuist-org",
      customer_id: "customer_id",
      creator: user
    )

    Billing
    |> stub(:get_customer_by_id, fn _ ->
      %{
        id: "customer_id",
        email: "customer_email"
      }
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

    Accounts
    |> stub(:get_current_month_remote_cache_hits_count, fn _ -> 167 end)

    conn =
      conn
      |> assign(:selected_owner, "tuist-org")
      |> log_in_user(user)

    %{conn: conn, user: user}
  end

  test "renders billing when a user has no active plan", %{conn: conn} do
    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/settings/billing")

    # Then
    assert has_element?(lv, ".billing__overview__plan-card__plan-summary__info", "No plan")
    refute has_element?(lv, "button", "Downgrade")
    assert has_element?(lv, "button", "Upgrade")
    refute has_element?(lv, "button", "Current plan")
  end

  test "renders billing when a user has the air plan", %{conn: conn} do
    # Given
    Billing
    |> stub(:get_current_active_subscription, fn _ ->
      %{
        plan: :air,
        status: "active",
        default_payment_method: "payment_method_id"
      }
    end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/settings/billing")

    # Then
    assert has_element?(lv, ".billing__overview__plan-card__plan-summary__info", "Air plan")
    refute has_element?(lv, "button", "Downgrade")
    assert has_element?(lv, "button", "Upgrade")
    assert has_element?(lv, "button", "Current plan")
    assert has_element?(lv, "p", "167 of 200 remote cache hits")
  end

  test "renders billing when a user has the pro plan", %{conn: conn} do
    # Given
    Billing
    |> stub(:get_current_active_subscription, fn _ ->
      %{
        plan: :pro,
        status: "active",
        default_payment_method: "payment_method_id"
      }
    end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/settings/billing")

    # Then
    assert has_element?(lv, ".billing__overview__plan-card__plan-summary__info", "Pro plan")
    assert has_element?(lv, "button", "Downgrade")
    refute has_element?(lv, "button", "Upgrade")
    assert has_element?(lv, "button", "Current plan")
    assert has_element?(lv, "p", "167 of 2000 remote cache hits")
  end

  test "renders billing when a user has the enterprise plan", %{conn: conn} do
    # Given
    Billing
    |> stub(:get_current_active_subscription, fn _ ->
      %{
        plan: :enterprise,
        status: "active",
        default_payment_method: "payment_method_id"
      }
    end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/tuist-org/settings/billing")

    # Then
    assert has_element?(
             lv,
             ".billing__overview__plan-card__plan-summary__info",
             "Enterprise plan"
           )

    assert has_element?(lv, "button", "Downgrade")
    refute has_element?(lv, "button", "Upgrade")
    assert has_element?(lv, "button", "Current plan")
  end

  test "raises UnauthorizedError when the user is not authorized to update billing", %{
    conn: conn,
    user: user
  } do
    # Given
    organization =
      AccountsFixtures.organization_fixture(preloads: [:account])

    Accounts.add_user_to_organization(user, organization)

    # When / Then
    assert_raise TuistCloudWeb.Errors.UnauthorizedError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/settings/billing")
    end
  end

  test "raises NotFoundError when the plan is invalid", %{conn: conn, user: user} do
    # Given
    organization = AccountsFixtures.organization_fixture(creator: user, preloads: [:account])

    # When / Then
    assert_raise TuistCloudWeb.Errors.NotFoundError, fn ->
      conn
      |> live(~p"/#{organization.account.name}/settings/billing?new_plan=invalid")
    end
  end
end
