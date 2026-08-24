defmodule TuistWeb.BillingLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Trials
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

      refute render(lv) =~ "prepaid"
    end

    test "counts prepaid minutes toward the runner ceiling", %{conn: conn, account: account} do
      runner_session_fixture(account, 40)

      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(300_000, :USD),
          granted: Money.new(750_000, :USD),
          granted_minutes: 10_000,
          expires_at: ~U[2026-09-01 00:00:00Z],
          grants: []
        }
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      html = render(lv)
      # Prepaid minutes are already paid for, so they raise the ceiling
      # rather than appearing as a balance of their own.
      assert html =~ "10100"
      assert html =~ "100 free plus 10,000 prepaid"
      # Nothing here may move as credit is spent.
      refute html =~ "3000.00"
      refute html =~ "left."
    end
  end

  describe "runner usage" do
    defp runner_session_fixture(account, minutes) do
      started = DateTime.add(DateTime.utc_now(), -2, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-staging-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, minutes * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end

    defp runner_session_at(account, started, minutes) do
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-staging-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, minutes * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end

    test "shows sub-minute usage rather than hiding it as zero", %{conn: conn, account: account} do
      # 18 seconds is real usage worth real money. Gating the card on
      # whole minutes hid it entirely, which reads as though nothing ran.
      started = DateTime.add(DateTime.utc_now(), -2, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-staging-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 18, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # Under a minute is still usage, so the row appears; the detail of
      # what it is worth lives on the usage page.
      assert render(lv) =~ "Runner minutes:"
    end

    test "counts the subscription's cycle rather than the calendar month", %{conn: conn, account: account} do
      # A subscription renewing mid-month bills on its own cycle, so usage
      # from before the cycle opened belongs to an invoice already sent.
      # Both sessions sit inside the current calendar month but only one
      # inside the cycle, so reading the wrong window shows both. Kept to
      # hours rather than days so the older one cannot fall into the
      # previous month and stop discriminating.
      now = DateTime.utc_now()
      period_start = DateTime.add(now, -1, :hour)

      stub(Billing, :current_billing_period, fn _account ->
        {period_start, DateTime.shift(period_start, month: 1)}
      end)

      runner_session_at(account, DateTime.add(now, -25, :hour), 500)
      # Ends before now, so the whole run falls inside the window rather
      # than being clipped at the period end.
      runner_session_at(account, DateTime.add(now, -45, :minute), 37)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      value = lv |> element("#runner-minutes-progress [data-part='value']") |> render()

      assert value =~ "37"
      # 537 would mean the window reached back past the cycle boundary.
      refute value =~ "537"
    end

    test "is not shown for an account that has run none", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      refute has_element?(lv, "#runner-usage-table")
    end

    test "is shown for an account holding prepaid minutes it has not spent", %{conn: conn, account: account} do
      # The bar answers "how much can I still run", and an account that
      # bought minutes and has run nothing yet is exactly when that
      # question has an interesting answer. Hiding it on zero usage
      # loses the minutes it paid for.
      stub(Prepaid, :balance, fn _account ->
        %{
          available: Money.new(750_000, :USD),
          granted: Money.new(750_000, :USD),
          granted_minutes: 10_000,
          expires_at: ~U[2027-08-20 00:00:00Z],
          grants: []
        }
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      assert has_element?(lv, "#runner-minutes-progress")
      assert render(lv) =~ "10,100"
    end

    test "separates what usage is worth from what is billed while on a trial", %{conn: conn, account: account} do
      runner_session_fixture(account, 100)
      {:ok, _account} = Trials.start(account)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      # The billing page carries the simple figure: minutes used against
      # the allowance. The money breakdown lives on the usage page.
      html = render(lv)
      assert html =~ "Runner minutes:"
      assert html =~ "100"
    end

    test "links to the breakdown rather than repeating it", %{conn: conn, account: account} do
      runner_session_fixture(account, 40)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      assert render(lv) =~ "See the breakdown"
    end

    test "counts whole minutes against the allowance", %{conn: conn, account: account} do
      # 90 seconds of runner time is one billable minute, not one and a half.
      runner_session_fixture(account, 1)
      session = Repo.one!(from(s in RunnerSession, where: s.account_id == ^account.id))

      Repo.update!(Ecto.Changeset.change(session, job_ended_at: DateTime.add(session.job_started_at, 90, :second)))

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/billing")

      assert render(lv) =~ "Runner minutes:"
    end
  end
end
