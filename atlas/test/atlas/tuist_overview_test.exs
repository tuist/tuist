defmodule Atlas.TuistOverviewTest do
  use ExUnit.Case, async: true

  alias Atlas.TuistOverview

  @range {~D[2026-09-01], ~D[2026-09-30]}

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

          String.contains?(sql, "cache_events") ->
            {:ok, %{"rows" => [%{"day" => "2026-09-10", "c" => "500"}]}}
        end
      end

      pg_query = fn _sql, _opts ->
        {:ok,
         %{
           "rows" => [%{"total_now" => 0, "total_before_previous" => 0, "total_before_current" => 0, "daily_new" => []}]
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
      # Series is padded to every day inside the window.
      assert length(jobs.series) == Date.diff(elem(@range, 1), elem(@range, 0)) + 1

      assert {:ok, cache} = measurements.cache_operations
      assert cache.total == 500
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
