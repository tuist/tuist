defmodule TuistWeb.UsageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.UsageLive

  @render_async_timeout 1_000

  setup :set_mimic_from_context

  setup do
    # Keeps the page off the network: the balance comes from Stripe and
    # the period from the subscription, neither of which a render test
    # should depend on.
    stub(Prepaid, :balance, fn _account -> nil end)
    stub(Tuist.Billing, :current_billing_period, fn _account -> nil end)
    :ok
  end

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "usage-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  defp trial_breakdown do
    %{
      period_start: ~D[2026-08-24],
      period_end: ~D[2026-09-24],
      usage_through: ~D[2026-08-25],
      minutes: 1_000,
      free_minutes: 100,
      gross: Money.new(7_500, :USD),
      trial_covered: Money.new(7_500, :USD),
      billed: Money.new(0, :USD),
      days: [],
      by_repository: [],
      projected_days: [],
      platforms: [
        %{
          id: "macos",
          platform: :macos,
          minutes: 1_000,
          projected_minutes: 1_000,
          # Nothing is billable while the trial runs, so the allowance
          # has no line of its own.
          included_minutes: nil,
          previous_minutes: 0,
          gross: Money.new(7_500, :USD),
          trial_covered: Money.new(7_500, :USD),
          billed: Money.new(0, :USD)
        }
      ]
    }
  end

  defp billed_breakdown do
    %{
      period_start: ~D[2026-08-24],
      period_end: ~D[2026-09-24],
      usage_through: ~D[2026-08-25],
      minutes: 1_000,
      free_minutes: 100,
      gross: Money.new(7_500, :USD),
      trial_covered: Money.new(0, :USD),
      billed: Money.new(6_750, :USD),
      days: [],
      by_repository: [],
      projected_days: [],
      platforms: [
        %{
          id: "macos",
          platform: :macos,
          minutes: 1_000,
          projected_minutes: 1_000,
          included_minutes: 100,
          previous_minutes: 0,
          gross: Money.new(7_500, :USD),
          trial_covered: Money.new(0, :USD),
          billed: Money.new(6_750, :USD)
        }
      ]
    }
  end

  defp previous_period_path(account) do
    now = DateTime.utc_now()
    previous = Timex.shift(%{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}, months: -1)

    "/#{account.name}/usage?period=#{Date.to_iso8601(DateTime.to_date(previous))}"
  end

  defp enable_kura(account) do
    stub(Environment, :dev?, fn -> false end)
    stub_kura_flag(account, true)
  end

  defp disable_kura(account) do
    stub(Environment, :dev?, fn -> false end)
    # Kura is on by default on non-hosted deployments, so the flag only gates
    # visibility on the hosted server.
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub_kura_flag(account, false)
  end

  defp stub_kura_flag(account, enabled?) do
    account_id = account.id

    stub(FunWithFlags, :enabled?, fn
      :kura, [for: %{id: ^account_id}] -> enabled?
      flag, opts -> Mimic.call_original(FunWithFlags, :enabled?, [flag, opts])
    end)
  end

  defp insert_event(attrs) do
    base = %{
      event_id: "evt-#{System.unique_integer([:positive])}",
      project_id: 0,
      node_id: "kura-test",
      region: "us-east-1",
      traffic_plane: "public",
      direction: "egress",
      operation: "download",
      protocol: "http",
      artifact_kind: "xcframework",
      bytes: 0,
      request_count: 0,
      window_start: NaiveDateTime.utc_now(:second),
      window_seconds: 3_600,
      inserted_at: NaiveDateTime.utc_now(:second)
    }

    IngestRepo.insert_all(UsageEvent, [Map.merge(base, attrs)])
  end

  describe "runner usage on a trial" do
    test "is shown even though nothing is billed", %{conn: conn, account: account} do
      # A trial account is metered and reported like any other, and the
      # page is where it looks to see what it has used. Hiding the
      # section until the first minute lands leaves it with nothing to
      # look at during the trial the section exists to support.
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      stub(Trials, :on_trial?, fn _account -> true end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      assert has_element?(lv, "[data-part='runner-usage-card']")
    end

    test "shows what the trial covered rather than a receipt that does not add up", %{conn: conn, account: account} do
      # Without this the receipt reads "1,000 minutes run, 75.00$" and
      # then "Billed 0.00$", with nothing saying where the money went.
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)

      stub(Allowance, :period_breakdown, fn _account -> trial_breakdown() end)
      stub(Allowance, :period_breakdown, fn _account, _period -> trial_breakdown() end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render(lv)

      assert html =~ "Covered by your trial"
      # The full value in, the same value out, nothing left to pay.
      assert html =~ "75.00"
      assert html =~ "−75.00"
    end

    test "does not deduct from a platform that has no rate yet", %{conn: conn, account: account} do
      # Linux has no agreed rate, so its value reads as a dash. Taking a
      # dash off a dash rendered "−—", which is not a number and not an
      # explanation.
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)

      breakdown = %{
        trial_breakdown()
        | platforms: [
            %{
              id: "linux",
              platform: :linux,
              minutes: 90,
              projected_minutes: 90,
              included_minutes: nil,
              previous_minutes: 0,
              gross: nil,
              trial_covered: nil,
              billed: nil
            }
          ]
      }

      stub(Allowance, :period_breakdown, fn _account -> breakdown end)
      stub(Allowance, :period_breakdown, fn _account, _period -> breakdown end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render(lv)

      assert html =~ "90 minutes run"
      refute html =~ "−—"
      refute html =~ "Covered by your trial"
    end

    test "is hidden for an account with neither runners nor usage", %{conn: conn, account: account} do
      enable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> false end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      refute has_element?(lv, "[data-part='runner-usage-card']")
    end
  end

  describe "runner usage with prepaid credit" do
    setup %{account: account} do
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      stub(Allowance, :period_breakdown, fn _account -> billed_breakdown() end)
      stub(Allowance, :period_breakdown, fn _account, _period -> billed_breakdown() end)
      :ok
    end

    test "shows what is left to pay once the credit is drawn down", %{conn: conn, account: account} do
      # The widget read "what lands on your invoice" and gave the usage
      # charge, while the receipt an inch below said nothing was left to
      # pay. Both figures were on screen and they disagreed.
      stub(Prepaid, :balance, fn _account -> %{available: Money.new(22_500, :USD)} end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      assert has_element?(lv, "#widget-runner-billed", "0.00")
      refute has_element?(lv, "#widget-runner-billed", "67.50")
    end

    test "shows the shortfall when the balance does not cover the period", %{conn: conn, account: account} do
      # 67.50$ of usage against a 20.00$ balance.
      stub(Prepaid, :balance, fn _account -> %{available: Money.new(2_000, :USD)} end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      assert has_element?(lv, "#widget-runner-billed", "47.50")
    end

    test "shows the usage charge itself for an account with no credit", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      assert has_element?(lv, "#widget-runner-billed", "67.50")
    end
  end

  describe "runner usage after a trial ends mid-period" do
    test "credits the trial and the allowance separately", %{conn: conn, account: account} do
      # The allowance line was rendered as gross minus billed, which is
      # the trial's credit and the allowance's added together. A period
      # part-covered by a trial therefore subtracted the trial twice and
      # the receipt stopped adding up.
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)

      breakdown = %{
        billed_breakdown()
        | trial_covered: Money.new(3_000, :USD),
          billed: Money.new(3_750, :USD),
          platforms: [
            %{
              id: "macos",
              platform: :macos,
              minutes: 1_000,
              projected_minutes: 1_000,
              included_minutes: 100,
              previous_minutes: 0,
              gross: Money.new(7_500, :USD),
              trial_covered: Money.new(3_000, :USD),
              billed: Money.new(3_750, :USD)
            }
          ]
      }

      stub(Allowance, :period_breakdown, fn _account -> breakdown end)
      stub(Allowance, :period_breakdown, fn _account, _period -> breakdown end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render(lv)

      # 75.00$ run, 30.00$ of it covered by the trial, 7.50$ of the rest
      # covered by the allowance, 37.50$ billed.
      assert html =~ "−30.00"
      assert html =~ "−7.50"
      assert html =~ "37.50"
    end
  end

  describe "runner usage across billing periods" do
    setup %{account: account} do
      disable_kura(account)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      stub(Allowance, :period_breakdown, fn _account -> billed_breakdown() end)
      stub(Allowance, :period_breakdown, fn _account, _period -> billed_breakdown() end)
      :ok
    end

    test "does not put today's credit against a period that has closed", %{conn: conn, account: account} do
      # A balance is what the account holds now. The grants that covered a
      # closed period were drawn down when it was invoiced, so applying
      # today's balance to it reports an amount owed that has nothing to
      # do with the invoice that period actually produced.
      stub(Prepaid, :balance, fn _account -> %{available: Money.new(22_500, :USD)} end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      assert has_element?(lv, "#widget-runner-billed", "0.00")
      assert has_element?(lv, "[data-kind='prepaid']")

      render_patch(lv, previous_period_path(account))

      assert has_element?(lv, "#widget-runner-billed", "67.50")
      refute has_element?(lv, "[data-kind='prepaid']")
    end

    test "does not read the prepaid balance again when the period changes", %{conn: conn, account: account} do
      # `Prepaid.balance/2` does not cache a nil, so an account with no
      # credit pays a Stripe round trip for every read.
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      test_pid = self()

      stub(Prepaid, :balance, fn _account ->
        send(test_pid, :balance_read)
        nil
      end)

      render_patch(lv, previous_period_path(account))

      refute_received :balance_read
    end
  end

  describe "Kura feature flag gate" do
    test "raises 404 when Kura is not enabled for the account", %{conn: conn, account: account} do
      disable_kura(account)
      # Nor runners: the page exists for either, so both have to be off
      # for it to be missing.
      stub(FeatureFlags, :runners_enabled?, fn _account -> false end)

      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        live(conn, ~p"/#{account.name}/usage")
      end
    end

    test "renders the page when Kura is enabled", %{conn: conn, account: account} do
      enable_kura(account)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Usage"
      assert html =~ "Cache traffic"
      assert html =~ "Egress"
      assert html =~ "Ingress"
      assert html =~ "Requests"
    end

    test "renders the page on the hosted server when the flag is on", %{conn: conn, account: account} do
      # Positive coverage for the hosted branch: tuist_hosted? true disables
      # the `not tuist_hosted?()` disjunct, so the page renders only because
      # the :kura flag is on.
      stub(Environment, :dev?, fn -> false end)
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub_kura_flag(account, true)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Usage"
    end
  end

  describe "rendering" do
    setup %{account: account} do
      enable_kura(account)
      :ok
    end

    test "scopes the page to a billing period rather than a free range", %{conn: conn, account: account} do
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/usage")

      assert html =~ "Runner time and cache traffic billed to this account"
      assert html =~ "Billing period:"
      # Both the free-range and project controls are gone: the page
      # reports one period, and everything on it follows that period.
      refute html =~ "Last 30 days"
      refute html =~ "Project:"
      assert has_element?(lv, "#usage-period-dropdown")
    end

    test "shows the empty state when there's no Kura traffic", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render_async(lv, @render_async_timeout)

      assert html =~ "No cache traffic in this window yet"
    end

    test "renders the per-region table when events exist", %{conn: conn, account: account} do
      ProjectsFixtures.project_fixture(account: account, name: "ios")

      insert_event(%{
        account_id: account.id,
        node_id: "kura-test-node",
        bytes: 1_000_000,
        request_count: 5,
        window_start: NaiveDateTime.utc_now(:second)
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render_async(lv, @render_async_timeout)

      assert html =~ "Traffic by region"
      assert html =~ "us-east-1"
      refute html =~ "kura-test-node"
      # 1 MB rendered through ByteFormatter
      assert html =~ "MB"
    end
  end

  describe "widget switching" do
    # Each widget renders an `empty` variant (no `phx-value-widget` attribute)
    # when its bytes/count is zero, so seed at least one event of each kind so
    # the click wrappers always render in this describe block.
    setup %{account: account} do
      enable_kura(account)

      insert_event(%{account_id: account.id, direction: "egress", bytes: 1_000, request_count: 1})
      insert_event(%{account_id: account.id, direction: "ingress", bytes: 500, request_count: 1})

      :ok
    end

    test "egress is the default selected widget", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="egress"][data-selected]|)
    end

    test "clicking a widget patches the URL with ?widget=ingress", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      _ = render_async(lv, @render_async_timeout)

      lv
      |> element(~s|[phx-value-widget="ingress"]|)
      |> render_click()

      assert_patch(lv, ~p"/#{account.name}/usage?widget=ingress")
      assert has_element?(lv, ~s|[phx-value-widget="ingress"][data-selected]|)
    end

    test "honors widget=requests in the URL on initial mount", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage?widget=requests")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="requests"][data-selected]|)
    end

    test "ignores an unknown widget param and falls back to egress", %{
      conn: conn,
      account: account
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage?widget=bogus")

      _ = render_async(lv, @render_async_timeout)
      assert has_element?(lv, ~s|[phx-value-widget="egress"][data-selected]|)
    end
  end

  describe "runner usage receipt" do
    test "walks from minutes to money, showing the allowance as a credit", %{conn: conn, user: user} do
      account = user.account
      now = DateTime.utc_now()
      started = DateTime.add(now, -2, :hour)

      stub(Tuist.Billing, :current_billing_period, fn _account ->
        {DateTime.add(now, -15, :day), DateTime.add(now, 15, :day)}
      end)

      Tuist.Repo.insert!(%Tuist.Runners.RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 120 * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/usage")

      html = render(lv)
      assert html =~ "120 minutes run"
      assert html =~ "100 minutes included"
      assert html =~ "Billed this period"
      # The credit reads as money off the bill, not as a bare minute count.
      assert html =~ "−7.50"
      # 20 minutes past the allowance at the standard rate.
      assert html =~ "1.50"
      assert html =~ "On track for about"
    end
  end

  describe "runner_chart_series/2" do
    test "stacks the projected days onto the same bars as the spend" do
      # The projection has to share the axis and the stack with the
      # repositories, otherwise the days ahead land on their own bars
      # and the period reads as though it restarted.
      by_repository = [%{date: ~D[2026-08-21], repository: "tuist/tuist", total_ms: 600_000}]

      projected = [
        %{date: ~D[2026-08-22], total_ms: 600_000},
        %{date: ~D[2026-08-23], total_ms: 600_000}
      ]

      assert [spent, projection] = UsageLive.runner_chart_series(by_repository, projected)

      assert projection.name == "Projected"
      assert projection.stack == spent.stack

      dates = [~D[2026-08-21], ~D[2026-08-22], ~D[2026-08-23]]
      assert Enum.map(spent.data, &hd/1) == dates
      assert Enum.map(projection.data, &hd/1) == dates

      # Spend only on the day that happened, projection only on the days
      # that have not.
      assert [[_, spend], [_, +0.0], [_, +0.0]] = spent.data
      assert [[_, +0.0], [_, ahead], [_, ahead]] = projection.data
      assert spend > 0
      assert ahead > 0
    end

    test "labels the axis out to the end of the projection" do
      # The axis only labels its first and last date. Derived from spend
      # alone it stopped at today, so a period with days still ahead was
      # labelled as though it ended this morning.
      breakdown = %{
        by_repository: [%{date: ~D[2026-08-21], repository: "tuist/tuist", total_ms: 600_000}],
        projected_days: [%{date: ~D[2026-08-22], total_ms: 600_000}, %{date: ~D[2026-08-23], total_ms: 600_000}]
      }

      options = breakdown |> UsageLive.runner_chart_dates() |> UsageLive.runner_chart_options()

      assert options.xAxis.axisLabel.customValues == [~D[2026-08-21], ~D[2026-08-23]]
    end

    test "has no projected series for a period that is over" do
      by_repository = [%{date: ~D[2026-08-21], repository: "tuist/tuist", total_ms: 600_000}]

      assert [only] = UsageLive.runner_chart_series(by_repository, [])
      refute only.name == "Projected"
    end
  end
end
