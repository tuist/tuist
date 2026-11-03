defmodule Tuist.Runners.AllowanceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{account: user.account}
  end

  defp used_minutes(account, minutes) do
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

  defp ran_minutes(account, started, minutes) do
    # Session timestamps are microsecond-precision; callers pass whatever
    # precision the instant they care about happens to carry.
    started = %{started | microsecond: {elem(started.microsecond, 0), 6}}

    Repo.insert!(%RunnerSession{
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
      job_ended_at: DateTime.add(started, minutes * 60, :second),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  defp ran_linux_minutes(account, started, minutes, {vcpus, memory_gb, multiplier}) do
    started = %{started | microsecond: {elem(started.microsecond, 0), 6}}

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "tuist-linux",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      platform: :linux,
      vcpus: vcpus,
      memory_gb: memory_gb,
      billing_multiplier: multiplier,
      started_at: started,
      job_started_at: started,
      job_ended_at: DateTime.add(started, minutes * 60, :second),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  defp trial_ended(account, at) do
    account
    |> Ecto.Changeset.change(
      runner_trial_started_at: at |> DateTime.add(-30, :day) |> DateTime.truncate(:second),
      runner_trial_ended_at: DateTime.truncate(at, :second)
    )
    |> Repo.update!()
  end

  defp on_trial_since(account, at) do
    account
    |> Ecto.Changeset.change(runner_trial_started_at: DateTime.truncate(at, :second))
    |> Repo.update!()
  end

  describe "exhausted?/1" do
    # Usage is back-dated a couple of hours and counted per calendar month,
    # so against the real clock it falls in the previous month during the
    # first hours of the 1st.
    setup do
      stub(DateTime, :utc_now, fn -> ~U[2024-01-17 12:00:00.000000Z] end)
      :ok
    end

    test "a free account with room left may still dispatch", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, 40)

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 60
    end

    test "a free account is cut off once the allowance is spent", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, Allowance.free_monthly_minutes(:macos))

      assert Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 0
    end

    test "a free account's Linux minutes spend their share of the allowance", %{account: account} do
      # 160 minutes on a 16 vCPU / 64 GB Linux machine are 1,280 baseline
      # minutes, a little over half of the 2,500 free ones, so they spend 51
      # of the 100 macOS minutes.
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      started = DateTime.add(DateTime.utc_now(), -4, :hour)
      ran_linux_minutes(account, started, 160, {16, 64, Catalog.billing_multiplier(:linux, 16, 64)})

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 49
    end

    test "a free account is cut off once both platforms together spend the allowance", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      started = DateTime.add(DateTime.utc_now(), -4, :hour)
      ran_linux_minutes(account, started, 160, {16, 64, Catalog.billing_multiplier(:linux, 16, 64)})
      used_minutes(account, 49)

      assert Allowance.exhausted?(account)
    end

    test "a paid account is never cut off, because the excess is what it pays for", %{account: account} do
      used_minutes(account, Allowance.free_monthly_minutes(:macos) * 10)

      for plan <- [:pro, :enterprise] do
        stub(Billing, :effective_plan, fn _account -> plan end)
        refute Allowance.exhausted?(account), "expected #{plan} to keep dispatching"
      end
    end

    test "an account on a runner trial is never cut off", %{account: account} do
      # A trial is "uses runners without being billed for them", and a trial
      # account has no subscription, so effective_plan reports :air. Without
      # this the account is cut off at the baseline and the trial does not let
      # it run runners at all — which is the whole thing it grants.
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, Allowance.free_monthly_minutes(:macos) * 10)

      {:ok, account} = Trials.start(account)

      refute Allowance.exhausted?(account)
    end

    test "an account whose trial was cancelled is cut off again", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, Allowance.free_monthly_minutes(:macos))

      {:ok, account} = Trials.start(account)
      {:ok, account} = Trials.cancel(account)

      assert Allowance.exhausted?(account)
    end

    test "an account that has run nothing is not exhausted", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == Allowance.free_monthly_minutes(:macos)
    end
  end

  describe "minutes_used/1" do
    test "truncates to whole minutes, matching how the Price rounds", %{account: account} do
      # 90 seconds is one billable minute, not one and a half. The clock is
      # frozen so the run doesn't fall in the previous month on the 1st.
      stub(DateTime, :utc_now, fn -> ~U[2024-01-17 12:00:00.000000Z] end)
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
        job_ended_at: DateTime.add(started, 90, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      assert Allowance.minutes_used(account) == 1
    end
  end

  describe "free_monthly_minutes/1" do
    # Pins the production numbers, which have to equal the first tier of
    # each production runner Price. An environment can lower both together
    # (staging does), but that override is runtime config rather than
    # something to mutate global state in a test to observe.
    test "defaults to the production allowances, worth the same on each platform" do
      assert Allowance.free_monthly_minutes(:macos) == 100
      assert Allowance.free_monthly_minutes(:linux) == 2_500
    end
  end

  describe "allowance_minutes/1" do
    test "counts Linux at its share of the macOS allowance" do
      # 25 Linux minutes spend one macOS minute of the shared allowance.
      assert Allowance.allowance_minutes(%{macos: 30 * 60_000, linux: 250 * 60_000}) == 40
      assert Allowance.allowance_minutes(%{linux: 2_500 * 60_000}) == 100
      assert Allowance.allowance_minutes(%{}) == 0
    end
  end

  describe "period_breakdown/1" do
    setup do
      # No subscription in these fixtures, so the window is the calendar
      # month; stubbed so the fallback is exercised without Stripe.
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "projects every remaining day of an open period from the rate so far", %{account: account} do
      # Early in a period is exactly when the shape of the month ahead is
      # worth seeing, so the days after today carry the daily rate so far
      # rather than being left blank.
      used_minutes(account, 60)

      today = Date.utc_today()
      period_start = DateTime.new!(Date.add(today, -1), ~T[00:00:00], "Etc/UTC")
      period_end = DateTime.shift(period_start, month: 1)

      breakdown = Allowance.period_breakdown(account, {period_start, period_end})

      assert [first | _] = breakdown.projected_days
      assert first.date == Date.add(today, 1)
      assert List.last(breakdown.projected_days).date == period_end |> DateTime.to_date() |> Date.add(-1)
      # Two days into the period, 60 minutes averages to 30 a day.
      assert first.total_ms == 30 * 60_000
    end

    test "spends the allowance in date order, so the day it runs out is split", %{account: account} do
      # Three days of 60 minutes against a 100 minute allowance: the
      # first is entirely free, the second straddles the boundary, the
      # third is entirely billed.
      period_start =
        DateTime.new!(Date.add(Date.utc_today(), -3), ~T[00:00:00], "Etc/UTC")

      period_end = DateTime.add(period_start, 4, :day)

      for day <- 0..2 do
        ran_minutes(account, DateTime.add(period_start, day, :day), 60)
      end

      breakdown = Allowance.period_breakdown(account, {period_start, period_end})

      assert breakdown.minutes == 180
      # 180 minutes at $0.06, of which 80 are past the allowance.
      assert breakdown.gross == Money.new(1080, :USD)
      assert breakdown.billed == Money.new(480, :USD)

      [first, second, third] = breakdown.days
      assert first.gross == Money.new(360, :USD)
      assert first.billed == Money.new(0, :USD)
      # The allowance ran out 40 minutes into this day.
      assert second.gross == Money.new(360, :USD)
      assert second.billed == Money.new(120, :USD)
      assert third.gross == Money.new(360, :USD)
      assert third.billed == Money.new(360, :USD)
    end

    test "gives every day a stable id, since the table keys rows on it", %{account: account} do
      started = DateTime.add(DateTime.utc_now(), -1, :day)

      Repo.insert!(%RunnerSession{
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
        job_ended_at: DateTime.add(started, 600, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      breakdown = Allowance.period_breakdown(account)

      ids = Enum.map(breakdown.days, & &1.id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(ids, &is_binary/1)
    end

    test "reports nothing for an account that has run no jobs", %{account: account} do
      breakdown = Allowance.period_breakdown(account)

      assert breakdown.minutes == 0
      assert breakdown.days == []
      assert breakdown.billed == Money.new(0, :USD)
    end
  end

  describe "period_breakdown/1 platform rows" do
    setup do
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "reports the period, its projection, what is included and the period before", %{account: account} do
      # 60 minutes on the 1st of the period, so the projection scales a
      # known figure across a known stretch of it. The clock is frozen
      # because the projection divides by elapsed seconds: against the
      # real clock the same usage projects to a different figure
      # depending on the hour of the day and the length of the month the
      # test happens to run in.
      now = ~U[2024-01-17 00:00:00.000000Z]
      stub(DateTime, :utc_now, fn -> now end)
      started = %{now | day: 1}

      Repo.insert!(%RunnerSession{
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
        job_ended_at: DateTime.add(started, 60 * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      assert [row, _linux] = Allowance.period_breakdown(account).platforms

      assert row.platform == :macos
      assert row.id == "macos"
      assert row.minutes == 60
      assert row.included_minutes == Allowance.free_monthly_minutes(:macos)
      assert row.previous_minutes == 0
      assert row.gross == Money.new(360, :USD)
      # Inside the allowance, so nothing of it is billable yet.
      assert row.billed == Money.new(0, :USD)

      # Straight-line to the end of the window: 60 minutes over the 16
      # elapsed days of a 31-day month, which is 116 minutes and a
      # quarter by the end of it.
      assert row.projected_minutes == 116
      assert row.projected_minutes >= row.minutes
    end

    test "bills Linux past its own free tier, at its own rate", %{account: account} do
      # 2,660 minutes on the 2 vCPU / 8 GB baseline is 160 past the 2,500
      # free ones, and at $0.0024 those are 38.4 cents. macOS sits inside
      # its own allowance.
      stub(DateTime, :utc_now, fn -> ~U[2024-01-17 12:00:00.000000Z] end)
      started = DateTime.add(DateTime.utc_now(), -4, :hour)

      ran_linux_minutes(account, started, 2_660, {2, 8, 10_000})
      ran_minutes(account, started, 60)

      breakdown = Allowance.period_breakdown(account)

      assert breakdown.minutes == 2_720
      assert breakdown.free_minutes == %{macos: 100, linux: 2_500}
      assert breakdown.gross == Money.new(360 + 638, :USD)
      assert breakdown.billed == Money.new(38, :USD)

      assert [day] = breakdown.days
      assert day.minutes == 2_720
      assert day.gross == Money.new(360 + 638, :USD)
      assert day.billed == Money.new(38, :USD)

      assert [macos, linux] = breakdown.platforms
      assert macos.billed == Money.new(0, :USD)
      assert linux.platform == :linux
      assert linux.minutes == 2_660
      assert linux.gross == Money.new(638, :USD)
      assert linux.billed == Money.new(38, :USD)
      assert linux.included_minutes == 2_500
    end

    test "costs a larger Linux machine by its multiplier", %{account: account} do
      # 16 vCPU / 64 GB is eight baseline units, so 400 minutes on it are
      # 3,200 baseline minutes at $0.0192 a minute: $7.68, of which the
      # 700 past the free 2,500 are billed, $1.68.
      stub(DateTime, :utc_now, fn -> ~U[2024-01-17 12:00:00.000000Z] end)
      started = DateTime.add(DateTime.utc_now(), -8, :hour)

      ran_linux_minutes(account, started, 400, {16, 64, Catalog.billing_multiplier(:linux, 16, 64)})

      breakdown = Allowance.period_breakdown(account)

      assert breakdown.gross == Money.new(768, :USD)
      assert breakdown.billed == Money.new(168, :USD)
      assert [_macos, %{gross: gross, minutes: 3_200}] = breakdown.platforms
      assert gross == Money.new(768, :USD)
    end

    test "keeps each platform's free tier to itself", %{account: account} do
      # 90 macOS minutes stay inside the macOS allowance however far past
      # its own Linux ran before them.
      period_start = DateTime.new!(Date.add(Date.utc_today(), -2), ~T[00:00:00], "Etc/UTC")
      period_end = DateTime.add(period_start, 3, :day)

      ran_linux_minutes(account, period_start, 2_700, {2, 8, 10_000})
      ran_minutes(account, DateTime.add(period_start, 1, :day), 90)

      breakdown = Allowance.period_breakdown(account, {period_start, period_end})

      # 2,700 Linux minutes at $0.0024 are $6.48, the 200 past the free
      # tier 48 cents; the macOS $5.40 is free.
      assert breakdown.gross == Money.new(648 + 540, :USD)
      assert breakdown.billed == Money.new(48, :USD)
    end

    test "costs a macOS receipt by compute units, as Stripe is metered", %{account: account} do
      # The 12 vCPU / 28 GB Mac is two baseline units, so an hour on it is
      # two hours of the allowance and $7.20 of usage.
      stub(DateTime, :utc_now, fn -> ~U[2024-01-17 12:00:00.000000Z] end)
      started = DateTime.add(DateTime.utc_now(), -4, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 12,
        memory_gb: 28,
        billing_multiplier: 20_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 60 * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      assert [macos, _linux] = Allowance.period_breakdown(account).platforms
      assert macos.minutes == 120
      assert macos.gross == Money.new(720, :USD)
      assert macos.billed == Money.new(120, :USD)
    end

    test "reports the macOS and Linux rows in that order", %{account: account} do
      assert account |> Allowance.period_breakdown() |> Map.fetch!(:platforms) |> Enum.map(& &1.platform) == [
               :macos,
               :linux
             ]
    end

    test "reports the priced platform for an account that ran nothing", %{account: account} do
      # An account has an allowance whether or not it has run anything,
      # and a receipt reading zero says that better than no receipt.
      assert [row, _linux] = Allowance.period_breakdown(account).platforms

      assert row.platform == :macos
      assert row.minutes == 0
      assert row.gross == Money.new(0, :USD)
      assert row.billed == Money.new(0, :USD)
      assert row.included_minutes == Allowance.free_monthly_minutes(:macos)
    end
  end

  describe "period_breakdown/1 runner trials" do
    setup do
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "prices nothing the trial covered when it ended inside the period", %{account: account} do
      # Stripe bills the runner item from the instant the trial ended, so
      # a period that straddles the cancellation is part covered and part
      # billable. Pricing the whole of it showed a bill no invoice was
      # going to carry.
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 60)
      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      # Every minute it ran, priced at the standard rate.
      assert breakdown.minutes == 240
      assert breakdown.gross == Money.new(1440, :USD)
      assert breakdown.trial_covered == Money.new(360, :USD)
      # 180 billable minutes, 100 of them included. The trial's 60 must
      # not have eaten the allowance on their way past.
      assert breakdown.billed == Money.new(480, :USD)
    end

    test "counts only the part of a run that fell after the trial ended", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      trial_end = now |> DateTime.add(-6, :hour) |> DateTime.truncate(:second)
      account = trial_ended(account, trial_end)

      ran_minutes(account, DateTime.add(trial_end, -60, :minute), 120)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.minutes == 120
      assert breakdown.gross == Money.new(720, :USD)
      assert breakdown.trial_covered == Money.new(360, :USD)
      assert breakdown.billed == Money.new(0, :USD)
    end

    test "leaves a day that ran wholly inside the trial with nothing billed", %{account: account} do
      # Past the allowance, so a day the trial covered has to be zeroed
      # deliberately rather than by the free tier happening to reach it.
      now = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[12:00:00], "Etc/UTC")
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 180)

      assert [day] = Allowance.period_breakdown(account, period).days
      assert day.gross == Money.new(1080, :USD)
      assert day.billed == Money.new(0, :USD)
    end

    test "prices the whole period once the trial ended before it started", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -2, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -10, :day))

      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.trial_covered == Money.new(0, :USD)
      assert breakdown.billed == Money.new(480, :USD)
    end

    test "prices a period that closed before the trial began", %{account: account} do
      # The usage page offers a year of history. A trial that starts today
      # says nothing about a period that was invoiced months ago, and
      # reading the trial's end alone marked every one of them covered.
      now = DateTime.utc_now()
      period = {DateTime.add(now, -10, :day), DateTime.add(now, -6, :day)}
      account = on_trial_since(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -8, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.trial_covered == Money.new(0, :USD)
      assert breakdown.billed == Money.new(480, :USD)
    end

    test "covers only what ran after the trial started", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = on_trial_since(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 180)
      ran_minutes(account, DateTime.add(now, -1, :day), 60)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.minutes == 240
      assert breakdown.gross == Money.new(1440, :USD)
      assert breakdown.trial_covered == Money.new(360, :USD)
      assert breakdown.billed == Money.new(480, :USD)
    end

    test "prices nothing at all while the trial is still running", %{account: account} do
      # This is the one trial case that takes the default window, which
      # is the calendar month, so the trial only covers the whole of it
      # when it started before the 1st. The clock is frozen because on
      # the 31st a trial that started 30 days ago starts inside the
      # month, and on the 1st a run four hours ago falls before it.
      now = ~U[2024-01-17 12:00:00.000000Z]
      stub(DateTime, :utc_now, fn -> now end)

      account = on_trial_since(account, DateTime.add(now, -30, :day))
      ran_minutes(account, DateTime.add(now, -4, :hour), 180)

      breakdown = Allowance.period_breakdown(account)

      assert breakdown.gross == Money.new(1080, :USD)
      assert breakdown.trial_covered == Money.new(1080, :USD)
      assert breakdown.billed == Money.new(0, :USD)

      # An allowance the account cannot reach yet is not a line worth
      # showing; the trial already covers everything above it.
      assert [row, _linux] = breakdown.platforms
      assert row.trial_covered == Money.new(1080, :USD)
      assert row.billed == Money.new(0, :USD)
      assert row.included_minutes == nil
    end

    test "bills a platform row only for what ran after the trial", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 60)
      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      assert [row, _linux] = Allowance.period_breakdown(account, period).platforms

      assert row.minutes == 240
      assert row.gross == Money.new(1440, :USD)
      assert row.trial_covered == Money.new(360, :USD)
      assert row.billed == Money.new(480, :USD)
      assert row.included_minutes == Allowance.free_monthly_minutes(:macos)
    end
  end
end
