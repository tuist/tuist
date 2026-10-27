defmodule Atlas.Nudges.AnalyticsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Nudges.Analytics.Reading
  alias Atlas.Repo

  describe "cache_effectiveness/2" do
    test "returns :insufficient_history when there are no buckets yet" do
      account = insert_account!()
      assert %Reading{stage: :insufficient_history, ratio: nil} = Analytics.cache_effectiveness(account)
    end

    test "returns :insufficient_history until the requested window is fully covered" do
      account = insert_account!()
      insert_bucket!(account, Date.utc_today() |> Date.add(-1), cache_hits: 10, cache_lookups: 20)
      insert_bucket!(account, Date.utc_today() |> Date.add(-2), cache_hits: 10, cache_lookups: 20)

      assert %Reading{stage: :insufficient_history, bucket_count: 2} =
               Analytics.cache_effectiveness(account, window: 7)
    end

    test "returns :insufficient_sample when the denominator is below the minimum" do
      account = insert_account!()

      for offset <- 1..7 do
        insert_bucket!(account, Date.utc_today() |> Date.add(-offset),
          cache_hits: 3,
          cache_lookups: 6
        )
      end

      assert %Reading{stage: :insufficient_sample, denominator: 42} =
               Analytics.cache_effectiveness(account, window: 7, min_denominator: 200)
    end

    test "returns :ok with the ratio when sample is sufficient" do
      account = insert_account!()

      for offset <- 1..7 do
        insert_bucket!(account, Date.utc_today() |> Date.add(-offset),
          cache_hits: 40,
          cache_lookups: 100
        )
      end

      assert %Reading{stage: :ok, numerator: 280, denominator: 700, ratio: ratio} =
               Analytics.cache_effectiveness(account, window: 7, min_denominator: 200)

      assert_in_delta ratio, 0.4, 0.0001
    end

    test "returns :failed when the most recent bucket is a failed refresh" do
      account = insert_account!()

      for offset <- 2..8 do
        insert_bucket!(account, Date.utc_today() |> Date.add(-offset),
          cache_hits: 40,
          cache_lookups: 100
        )
      end

      insert_bucket!(account, Date.utc_today() |> Date.add(-1),
        cache_hits: 0,
        cache_lookups: 0,
        refresh_status: "failed",
        refresh_error: "clickhouse: timeout"
      )

      assert %Reading{stage: :failed} = Analytics.cache_effectiveness(account, window: 7)
    end

    test "returns :stale when the most recent bucket is older than the staleness threshold" do
      account = insert_account!()

      insert_bucket!(account, Date.utc_today() |> Date.add(-1),
        cache_hits: 40,
        cache_lookups: 100,
        computed_at: DateTime.utc_now() |> DateTime.add(-72, :hour) |> DateTime.truncate(:second)
      )

      for offset <- 2..7 do
        insert_bucket!(account, Date.utc_today() |> Date.add(-offset),
          cache_hits: 40,
          cache_lookups: 100
        )
      end

      assert %Reading{stage: :stale} =
               Analytics.cache_effectiveness(account, window: 7, staleness_hours: 48)
    end
  end

  describe "selective_testing_effectiveness/2" do
    test "uses the selective-testing columns for its rollup" do
      account = insert_account!()

      for offset <- 1..7 do
        insert_bucket!(account, Date.utc_today() |> Date.add(-offset),
          selective_hits: 30,
          selective_targets: 60,
          cache_hits: 0,
          cache_lookups: 0
        )
      end

      assert %Reading{stage: :ok, numerator: 210, denominator: 420, ratio: ratio} =
               Analytics.selective_testing_effectiveness(account,
                 window: 7,
                 min_denominator: 100
               )

      assert_in_delta ratio, 0.5, 0.0001
    end
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "analytics:#{System.unique_integer([:positive])}",
      name: "Analytics Customer",
      segment: :customer,
      plan_tier: "pro"
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_bucket!(account, %Date{} = bucket_date, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    overrides =
      Map.new(opts, fn
        {:cache_hits, v} -> {:daily_cache_hits, v}
        {:cache_lookups, v} -> {:daily_cache_lookups, v}
        {:selective_hits, v} -> {:daily_selective_hits, v}
        {:selective_targets, v} -> {:daily_selective_targets, v}
        pair -> pair
      end)

    attrs =
      Map.merge(
        %{
          account_id: account.id,
          bucket_date: bucket_date,
          daily_cache_hits: 0,
          daily_cache_lookups: 0,
          daily_selective_hits: 0,
          daily_selective_targets: 0,
          refresh_status: "ok",
          computed_at: now
        },
        overrides
      )

    %MetricBucket{}
    |> MetricBucket.changeset(attrs)
    |> Repo.insert!()
  end
end
