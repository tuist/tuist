defmodule Atlas.TuistOverviewTest do
  use ExUnit.Case, async: true

  alias Atlas.TuistOverview

  @range {~D[2026-09-01], ~D[2026-09-30]}

  describe "granularity/2" do
    test "groups by day for windows of up to 30 days" do
      assert TuistOverview.granularity(~D[2026-09-22], ~D[2026-09-22]) == :day
      assert TuistOverview.granularity(~D[2026-09-01], ~D[2026-09-30]) == :day
    end

    test "groups by week for windows longer than 30 days and up to six months" do
      assert TuistOverview.granularity(~D[2026-08-31], ~D[2026-09-30]) == :week
      assert TuistOverview.granularity(~D[2026-03-23], ~D[2026-09-22]) == :week
      assert TuistOverview.granularity(~D[2026-03-01], ~D[2026-08-31]) == :week
    end

    test "groups by month for windows longer than six months" do
      assert TuistOverview.granularity(~D[2026-03-22], ~D[2026-09-22]) == :month
      assert TuistOverview.granularity(~D[2026-02-28], ~D[2026-08-31]) == :month
      assert TuistOverview.granularity(~D[2025-09-23], ~D[2026-09-22]) == :month
    end
  end

  describe "measure_metric/3 grouping" do
    @empty_pg_row %{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}

    test "sums event counts per calendar week, keying the partial first week by the window start" do
      ch_query = fn _sql, opts ->
        rows =
          if opts[:params]["start_ts"] == "2026-08-01 00:00:00" do
            [
              %{"day" => "2026-08-01", "c" => 10},
              %{"day" => "2026-08-02", "c" => 5},
              %{"day" => "2026-08-05", "c" => 7},
              %{"day" => "2026-09-30", "c" => 3}
            ]
          else
            []
          end

        {:ok, %{"rows" => rows}}
      end

      assert {:ok, jobs} =
               TuistOverview.measure_metric(:jobs, {~D[2026-08-01], ~D[2026-09-30]},
                 configured?: fn -> true end,
                 pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
                 ch_query: ch_query
               )

      assert jobs.granularity == :week
      assert jobs.total == 25
      assert length(jobs.series) == 10
      assert Enum.take(jobs.series, 2) == [{~D[2026-08-01], 15}, {~D[2026-08-03], 7}]
      assert List.last(jobs.series) == {~D[2026-09-28], 3}
      assert Enum.sum(Enum.map(jobs.series, &elem(&1, 1))) == 25
    end

    test "keeps the last snapshot of each week for cumulative metrics" do
      pg_query = fn _sql, _opts ->
        {:ok,
         %{
           "rows" => [
             %{
               @empty_pg_row
               | "total_now" => 1000,
                 "total_before_current" => 900,
                 "daily_new" => [%{"day" => "2026-08-02", "c" => 5}, %{"day" => "2026-08-04", "c" => 10}]
             }
           ]
         }}
      end

      assert {:ok, users} =
               TuistOverview.measure_metric(:users, {~D[2026-08-01], ~D[2026-09-30]},
                 configured?: fn -> true end,
                 pg_query: pg_query,
                 ch_query: fn _sql, _opts -> flunk("clickhouse proxy should not be called") end
               )

      assert users.granularity == :week
      assert Enum.take(users.series, 3) == [{~D[2026-08-01], 905}, {~D[2026-08-03], 915}, {~D[2026-08-10], 915}]
    end

    test "averages daily active users per week and drops the daily trend line" do
      ch_query = fn _sql, opts ->
        rows =
          if opts[:params]["start_ts"] == "2026-08-01 00:00:00" do
            [
              %{"day" => "2026-08-01", "c" => 10},
              %{"day" => "2026-08-02", "c" => 20},
              %{"day" => "2026-08-03", "c" => 70}
            ]
          else
            []
          end

        {:ok, %{"rows" => rows}}
      end

      assert {:ok, active_users} =
               TuistOverview.measure_metric(:active_users, {~D[2026-08-01], ~D[2026-09-30]},
                 configured?: fn -> true end,
                 pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
                 ch_query: ch_query
               )

      assert active_users.granularity == :week
      refute Map.has_key?(active_users, :trend)
      assert Enum.take(active_users.series, 2) == [{~D[2026-08-01], 15}, {~D[2026-08-03], 10}]
    end

    test "sums event counts per calendar month for windows longer than six months" do
      ch_query = fn _sql, opts ->
        rows =
          if opts[:params]["start_ts"] == "2025-10-01 00:00:00" do
            [
              %{"day" => "2025-10-01", "c" => 1},
              %{"day" => "2025-10-31", "c" => 2},
              %{"day" => "2026-09-15", "c" => 4}
            ]
          else
            []
          end

        {:ok, %{"rows" => rows}}
      end

      assert {:ok, jobs} =
               TuistOverview.measure_metric(:jobs, {~D[2025-10-01], ~D[2026-09-30]},
                 configured?: fn -> true end,
                 pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
                 ch_query: ch_query
               )

      assert jobs.granularity == :month
      assert length(jobs.series) == 12
      assert List.first(jobs.series) == {~D[2025-10-01], 3}
      assert List.last(jobs.series) == {~D[2026-09-01], 4}
    end
  end

  describe "measure/2" do
    test "returns {:error, :not_configured} for every metric when the Tuist server is not configured" do
      measurements =
        TuistOverview.measure(@range,
          configured?: fn -> false end,
          pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
          ch_query: fn _sql, _opts -> flunk("clickhouse proxy should not be called") end
        )

      for metric <- TuistOverview.metrics() do
        assert Map.fetch!(measurements, metric) == {:error, :not_configured}
      end
    end

    test "returns cumulative totals + daily series for postgres-backed metrics" do
      pg_query = fn sql, _opts ->
        if String.contains?(sql, "FROM users") do
          {:ok,
           %{
             "rows" => [
               %{
                 "total_now" => 1000,
                 "total_before_previous" => 800,
                 "total_before_current" => 900,
                 "daily_new" => [
                   %{"day" => "2026-08-15", "c" => 10},
                   %{"day" => "2026-09-01", "c" => 5},
                   %{"day" => "2026-09-15", "c" => 20}
                 ]
               }
             ]
           }}
        else
          {:ok,
           %{
             "rows" => [
               %{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}
             ]
           }}
        end
      end

      ch_query = fn _sql, _opts -> {:ok, %{"rows" => []}} end

      measurements =
        TuistOverview.measure(@range,
          configured?: fn -> true end,
          pg_query: pg_query,
          ch_query: ch_query
        )

      assert {:ok, users} = measurements.users
      assert users.total == 1000
      # September series starts at total_before_current (900) and adds new
      # rows on each day (5 on the 1st, 20 on the 15th), staying flat between.
      assert List.first(users.series) == {~D[2026-09-01], 905}
      day_14 = Enum.find_value(users.series, fn {d, v} -> if d == ~D[2026-09-14], do: v end)
      assert day_14 == 905
      day_15 = Enum.find_value(users.series, fn {d, v} -> if d == ~D[2026-09-15], do: v end)
      assert day_15 == 925
      # Previous-period delta is total_now vs. total_before_current.
      assert users.previous_value == 900
      assert users.delta_pct == Float.round((1000 - 900) / 900 * 100.0, 1)
    end

    test "returns per-day event counts and previous-period totals for clickhouse-backed metrics" do
      ch_query = fn sql, opts ->
        cond do
          String.contains?(sql, "runner_jobs") ->
            # First call: previous period; second call: current period.
            params = opts[:params]
            start_ts = params["start_ts"]

            rows =
              if String.starts_with?(start_ts, "2026-09-") do
                [%{"day" => "2026-09-15", "c" => 100}, %{"day" => "2026-09-20", "c" => 50}]
              else
                [%{"day" => "2026-08-05", "c" => 30}]
              end

            {:ok, %{"rows" => rows}}

          String.contains?(sql, "reapi_cache_events") ->
            {:ok, %{"rows" => [%{"day" => "2026-09-10", "c" => "300"}]}}

          String.contains?(sql, "FROM command_events") ->
            {:ok, %{"rows" => [%{"day" => "2026-09-10", "c" => "200"}]}}
        end
      end

      pg_query = fn _sql, _opts ->
        {:ok,
         %{
           "rows" => [
             %{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}
           ]
         }}
      end

      measurements =
        TuistOverview.measure(@range,
          configured?: fn -> true end,
          pg_query: pg_query,
          ch_query: ch_query
        )

      assert {:ok, jobs} = measurements.jobs
      assert jobs.total == 150
      assert jobs.previous_value == 30
      # A 30-day window is grouped by day and padded to every day inside it.
      assert jobs.granularity == :day
      assert length(jobs.series) == Date.diff(elem(@range, 1), elem(@range, 0)) + 1

      assert {:ok, cache} = measurements.cache_operations
      assert cache.total == 500
    end

    test "averages the daily distinct counts for active users instead of summing them" do
      ch_query = fn sql, opts ->
        if String.contains?(sql, "uniqExact(user_id)") do
          rows =
            if String.starts_with?(opts[:params]["start_ts"], "2026-09-") do
              # Two of the 30 days in the window report a count; the rest are
              # padded with zeroes before averaging.
              [%{"day" => "2026-09-10", "c" => 600}, %{"day" => "2026-09-11", "c" => 900}]
            else
              [%{"day" => "2026-08-10", "c" => 310}]
            end

          {:ok, %{"rows" => rows}}
        else
          {:ok, %{"rows" => []}}
        end
      end

      pg_query = fn _sql, _opts ->
        {:ok,
         %{
           "rows" => [
             %{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}
           ]
         }}
      end

      measurements =
        TuistOverview.measure(@range,
          configured?: fn -> true end,
          pg_query: pg_query,
          ch_query: ch_query
        )

      assert {:ok, active_users} = measurements.active_users
      # 1500 across 30 days, not the 1500 a sum would report.
      assert active_users.current_value == 50
      assert active_users.previous_value == round(310 / 30)
      assert length(active_users.series) == 30

      assert Enum.find_value(active_users.series, fn {d, v} -> if d == ~D[2026-09-11], do: v end) == 900
      assert Enum.find_value(active_users.series, fn {d, v} -> if d == ~D[2026-09-12], do: v end) == 0
    end

    test "smooths active users into a seven-day trailing mean that starts at the first plotted day" do
      # One count per window, so every trailing mean is that count spread over
      # the seven days it stays inside the window.
      ch_query = fn sql, opts ->
        if String.contains?(sql, "uniqExact(user_id)") do
          rows =
            if String.starts_with?(opts[:params]["start_ts"], "2026-09-") do
              [%{"day" => "2026-09-10", "c" => 700}]
            else
              [%{"day" => "2026-08-31", "c" => 70}]
            end

          {:ok, %{"rows" => rows}}
        else
          {:ok, %{"rows" => []}}
        end
      end

      pg_query = fn _sql, _opts ->
        {:ok,
         %{
           "rows" => [
             %{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}
           ]
         }}
      end

      measurements =
        TuistOverview.measure(@range,
          configured?: fn -> true end,
          pg_query: pg_query,
          ch_query: ch_query
        )

      assert {:ok, %{trend: trend}} = measurements.active_users
      # Defined for the whole window, not just from the seventh day on.
      assert length(trend) == 30
      assert trend |> List.first() |> elem(0) == ~D[2026-09-01]

      trend_on = fn date -> Enum.find_value(trend, fn {d, v} -> if d == date, do: v end) end

      # Sep 1 still sees Aug 31's 70 in its trailing week, which only the
      # previous window can supply.
      assert trend_on.(~D[2026-09-01]) == 10
      # Aug 31 falls out of the window after seven days.
      assert trend_on.(~D[2026-09-07]) == 0
      # Sep 10's 700 spreads over the seven days it remains in the window.
      assert trend_on.(~D[2026-09-10]) == 100
      assert trend_on.(~D[2026-09-16]) == 100
      assert trend_on.(~D[2026-09-17]) == 0
    end

    test "in dev, returns deterministic sample data when the Tuist server is not configured" do
      previous_env = Application.get_env(:atlas, :env)
      Application.put_env(:atlas, :env, :dev)

      try do
        measurements =
          TuistOverview.measure(@range,
            configured?: fn -> false end,
            pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
            ch_query: fn _sql, _opts -> flunk("clickhouse proxy should not be called") end
          )

        for metric <- TuistOverview.metrics() do
          assert {:ok, %{series: [_ | _], total: total}} = Map.fetch!(measurements, metric)
          assert total > 0
        end
      after
        Application.put_env(:atlas, :env, previous_env)
      end
    end
  end
end
