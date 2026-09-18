defmodule Atlas.TuistOverviewTest do
  use ExUnit.Case, async: true

  alias Atlas.TuistOverview

  describe "stats/1" do
    test "returns {:error, :not_configured} for every stat when the Tuist server is not configured" do
      stats =
        TuistOverview.stats(
          configured?: fn -> false end,
          pg_query: fn _sql, _opts -> flunk("pg proxy should not be called") end,
          ch_query: fn _sql, _opts -> flunk("clickhouse proxy should not be called") end
        )

      for key <- [:users, :organizations, :projects, :jobs, :cache_operations] do
        assert Map.fetch!(stats, key) == {:error, :not_configured}
      end
    end

    test "returns per-stat counts pulled from the read-only proxies" do
      pg_responses = %{
        "users" => 42,
        "organizations" => 7,
        "projects" => 128,
        "runner_jobs" => 3500
      }

      pg_query = fn sql, _opts ->
        table = Enum.find(Map.keys(pg_responses), &String.contains?(sql, " #{&1}"))
        {:ok, %{"rows" => [%{"c" => Map.fetch!(pg_responses, table)}]}}
      end

      ch_query = fn sql, _opts ->
        assert sql =~ "cache_events"
        assert sql =~ "reapi_cache_events"
        assert sql =~ "gradle_cache_events"
        {:ok, %{"rows" => [%{"c" => 9_876_543}]}}
      end

      stats =
        TuistOverview.stats(configured?: fn -> true end, pg_query: pg_query, ch_query: ch_query)

      assert stats.users == {:ok, 42}
      assert stats.organizations == {:ok, 7}
      assert stats.projects == {:ok, 128}
      assert stats.jobs == {:ok, 3500}
      assert stats.cache_operations == {:ok, 9_876_543}
    end

    test "reports {:error, reason} for a single failing query without blanking the rest" do
      pg_query = fn
        "SELECT count(*) AS c FROM users", _opts -> {:error, :timeout}
        _sql, _opts -> {:ok, %{"rows" => [%{"c" => 1}]}}
      end

      ch_query = fn _sql, _opts -> {:ok, %{"rows" => [%{"c" => 2}]}} end

      stats =
        TuistOverview.stats(configured?: fn -> true end, pg_query: pg_query, ch_query: ch_query)

      assert stats.users == {:error, :timeout}
      assert stats.organizations == {:ok, 1}
      assert stats.cache_operations == {:ok, 2}
    end

    test "parses stringified counts returned by the proxies" do
      pg_query = fn _sql, _opts -> {:ok, %{"rows" => [%{"c" => "10"}]}} end
      ch_query = fn _sql, _opts -> {:ok, %{"rows" => [%{"c" => "20"}]}} end

      stats =
        TuistOverview.stats(configured?: fn -> true end, pg_query: pg_query, ch_query: ch_query)

      assert stats.users == {:ok, 10}
      assert stats.cache_operations == {:ok, 20}
    end
  end
end
