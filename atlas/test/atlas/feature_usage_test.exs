defmodule Atlas.FeatureUsageTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Audit.Activity
  alias Atlas.FeatureUsage
  alias Atlas.FeatureUsage.Catalog
  alias Atlas.FeatureUsage.Collector
  alias Atlas.Repo

  setup :verify_on_exit!

  defp account_with_handle!(handle \\ "acme") do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:#{System.unique_integer([:positive])}",
        name: "Acme",
        segment: :customer
      })
      |> Repo.insert!()

    %AccountHandle{}
    |> AccountHandle.changeset(%{account_id: account.id, handle: handle, source: "tuist"})
    |> Repo.insert!()

    account
  end

  # Build a full metrics list for every catalog feature, with per-slug overrides
  # of {events_last_24h, events_last_7d, events_prior_7d}.
  defp metrics(overrides) do
    Enum.map(Catalog.tracked(), fn feature ->
      {l24, l7, p7} = Map.get(overrides, feature.slug, {0, 0, 0})

      %{
        feature: feature.slug,
        events_last_24h: l24,
        events_last_7d: l7,
        events_prior_7d: p7,
        last_used_at: nil
      }
    end)
  end

  defp stub_collector(metrics) do
    stub(Collector, :resolve, fn _handle -> {:ok, %{account_id: 1, project_ids: [1]}} end)
    stub(Collector, :measure, fn _resolution -> {:ok, metrics} end)
  end

  defp silent_notify, do: fn _account, _snapshot, _change -> :ok end

  describe "refresh_account/2" do
    test "persists one snapshot per feature with derived active flags" do
      account = account_with_handle!()
      stub_collector(metrics(%{"cache" => {2, 5, 3}}))

      notify = fn _account, _snapshot, _change -> flunk("should not alert a steady-state feature") end

      assert {:ok, %{snapshots: snapshots}} = FeatureUsage.refresh_account(account.id, notify: notify)
      assert length(snapshots) == length(Catalog.tracked())

      cache = Enum.find(snapshots, &(&1.feature == "cache"))
      assert cache.active == true
      assert cache.active_previous == true
      assert cache.events_last_7d == 5
      assert Repo.get_by!(Activity, action: "account.feature_usage_refreshed", target_id: account.id)
    end

    test "alerts a :stopped on the first snapshot when a feature was used prior week but not the last" do
      account = account_with_handle!()
      # cache: dropped (prior 7d > 0, last 7d == 0); builds: still active.
      stub_collector(metrics(%{"cache" => {0, 0, 4}, "builds" => {1, 9, 2}}))

      parent = self()
      notify = fn _account, snapshot, change -> send(parent, {:notified, change, snapshot.feature}) end

      assert {:ok, %{alerts: alerts}} = FeatureUsage.refresh_account(account.id, notify: notify)
      assert Enum.map(alerts, fn {change, s} -> {change, s.feature} end) == [{:stopped, "cache"}]
      assert_received {:notified, :stopped, "cache"}
      refute_received {:notified, _change, "builds"}

      assert Repo.get_by!(Activity, action: "account.feature_usage_dropped", target_id: account.id)
    end

    test "alerts a :started on the first snapshot when a feature is active now but wasn't in the prior week" do
      account = account_with_handle!()
      # previews: adopted this week (last 7d > 0, prior 7d == 0).
      stub_collector(metrics(%{"previews" => {2, 5, 0}}))

      parent = self()
      notify = fn _account, snapshot, change -> send(parent, {:notified, change, snapshot.feature}) end

      assert {:ok, %{alerts: alerts}} = FeatureUsage.refresh_account(account.id, notify: notify)
      assert Enum.map(alerts, fn {change, s} -> {change, s.feature} end) == [{:started, "previews"}]
      assert_received {:notified, :started, "previews"}

      assert Repo.get_by!(Activity, action: "account.feature_usage_started", target_id: account.id)
    end

    test "does not alert a :started on the first snapshot when the feature was already active the prior week" do
      account = account_with_handle!()
      # cache: active both windows; steady state, no adoption alert.
      stub_collector(metrics(%{"cache" => {1, 5, 4}}))

      notify = fn _account, _snapshot, _change -> flunk("should not alert steady-state usage") end

      assert {:ok, %{alerts: []}} = FeatureUsage.refresh_account(account.id, notify: notify)
    end

    test "does not fire notifications for build-system slugs" do
      account = account_with_handle!()
      # system_xcode "starts" (prior 7d == 0, last 7d > 0). Build systems must not alert.
      stub_collector(metrics(%{"system_xcode" => {1, 3, 0}}))

      notify = fn _account, _snapshot, _change -> flunk("build systems must not raise notifications") end

      assert {:ok, %{alerts: []}} = FeatureUsage.refresh_account(account.id, notify: notify)
    end

    test "alerts on the active -> inactive transition across runs, and only once" do
      account = account_with_handle!()
      parent = self()
      notify = fn _account, snapshot, change -> send(parent, {:notified, change, snapshot.feature}) end

      # Day 1: builds active.
      stub_collector(metrics(%{"builds" => {5, 12, 8}}))

      assert {:ok, %{alerts: []}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-29 00:00:00Z], notify: notify)

      refute_received {:notified, _change, _feature}

      # Day 2: builds went silent -> transition alert.
      stub_collector(metrics(%{"builds" => {0, 0, 12}}))

      assert {:ok, %{alerts: alerts}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-30 00:00:00Z], notify: notify)

      assert Enum.map(alerts, fn {change, s} -> {change, s.feature} end) == [{:stopped, "builds"}]
      assert_received {:notified, :stopped, "builds"}

      # Day 3: still silent -> no repeat alert.
      stub_collector(metrics(%{"builds" => {0, 0, 0}}))

      assert {:ok, %{alerts: []}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-31 00:00:00Z], notify: notify)

      refute_received {:notified, _change, "builds"}
    end

    test "alerts on the inactive -> active transition across runs, and only once" do
      account = account_with_handle!()
      parent = self()
      notify = fn _account, snapshot, change -> send(parent, {:notified, change, snapshot.feature}) end

      # Day 1: sharding unused, both windows.
      stub_collector(metrics(%{"sharding" => {0, 0, 0}}))

      assert {:ok, %{alerts: []}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-29 00:00:00Z], notify: notify)

      refute_received {:notified, _change, _feature}

      # Day 2: sharding gets picked up -> adoption alert.
      stub_collector(metrics(%{"sharding" => {2, 4, 0}}))

      assert {:ok, %{alerts: alerts}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-30 00:00:00Z], notify: notify)

      assert Enum.map(alerts, fn {change, s} -> {change, s.feature} end) == [{:started, "sharding"}]
      assert_received {:notified, :started, "sharding"}

      # Day 3: still active -> no repeat.
      stub_collector(metrics(%{"sharding" => {1, 3, 4}}))

      assert {:ok, %{alerts: []}} =
               FeatureUsage.refresh_account(account.id, now: ~U[2026-07-31 00:00:00Z], notify: notify)

      refute_received {:notified, _change, "sharding"}
    end

    test "returns :not_found when the account has no Tuist handle" do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "account:#{System.unique_integer([:positive])}",
          name: "No Handle",
          segment: :lead
        })
        |> Repo.insert!()

      assert {:error, :not_found} = FeatureUsage.refresh_account(account.id)
    end
  end

  describe "reads" do
    test "latest_usage_for_account returns the newest snapshot per feature" do
      account = account_with_handle!()
      stub_collector(metrics(%{"cache" => {1, 1, 1}}))
      FeatureUsage.refresh_account(account.id, now: ~U[2026-07-29 00:00:00Z], notify: silent_notify())

      stub_collector(metrics(%{"cache" => {9, 9, 9}}))
      FeatureUsage.refresh_account(account.id, now: ~U[2026-07-30 00:00:00Z], notify: silent_notify())

      cache = account.id |> FeatureUsage.latest_usage_for_account() |> Enum.find(&(&1.feature == "cache"))
      assert cache.events_last_7d == 9
    end

    test "list_recent_stops returns transitions, filterable by feature" do
      account = account_with_handle!()
      stub_collector(metrics(%{"cache" => {0, 0, 5}, "builds" => {0, 0, 5}}))
      FeatureUsage.refresh_account(account.id, notify: silent_notify())

      stops = FeatureUsage.list_recent_stops()
      assert stops |> Enum.map(& &1.feature) |> Enum.sort() == ["builds", "cache"]

      only_cache = FeatureUsage.list_recent_stops(feature: "cache")
      assert Enum.map(only_cache, & &1.feature) == ["cache"]
      assert hd(only_cache).account.id == account.id
    end

    test "list_tracked_account_ids returns accounts with a Tuist handle" do
      account = account_with_handle!()
      assert account.id in FeatureUsage.list_tracked_account_ids()
    end
  end
end
