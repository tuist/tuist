defmodule Atlas.FeatureUsage.CollectorTest do
  use ExUnit.Case, async: true

  alias Atlas.FeatureUsage.Catalog
  alias Atlas.FeatureUsage.Collector

  describe "resolve/2" do
    test "returns the account id and project ids from the Postgres proxy" do
      parent = self()

      pg_query = fn sql, opts ->
        send(parent, {:pg, sql, opts})
        {:ok, %{"rows" => [%{"account_id" => 42, "project_ids" => [1, 2, 3]}]}}
      end

      assert {:ok, %{account_handle: "acme", account_id: 42, project_ids: [1, 2, 3]}} =
               Collector.resolve("acme", pg_query: pg_query)

      assert_receive {:pg, sql, opts}
      assert sql =~ "a.name = 'acme'"
      assert opts[:limit] == 1
    end

    test "parses project ids when the proxy returns them as a JSON string" do
      # The Postgres proxy serializes array_agg columns as a JSON string.
      pg_query = fn _sql, _opts ->
        {:ok, %{"rows" => [%{"account_id" => 1583, "project_ids" => "[1227]"}]}}
      end

      assert {:ok, %{account_handle: "qonto", account_id: 1583, project_ids: [1227]}} =
               Collector.resolve("qonto", pg_query: pg_query)
    end

    test "returns :not_found when no account matches" do
      assert {:error, :not_found} = Collector.resolve("ghost", pg_query: fn _sql, _opts -> {:ok, %{"rows" => []}} end)
    end

    test "rejects handles that are not plain slugs without querying" do
      pg_query = fn _sql, _opts -> flunk("should not query") end
      assert {:error, :invalid_handle} = Collector.resolve("bad handle!", pg_query: pg_query)
    end
  end

  # Each grouped query asks for per-member columns c0_*, c1_*, ...; return the
  # same values for every member index so we can assert parsing and summing.
  defp grouped_row do
    Enum.reduce(0..15, %{}, fn i, acc ->
      Map.merge(acc, %{
        "c#{i}_24h" => 3,
        "c#{i}_7d" => 10,
        "c#{i}_p7" => 7,
        "c#{i}_last" => "2026-07-29 08:30:00.000000"
      })
    end)
  end

  # `:configuration` features are counted through the Postgres proxy.
  defp configuration_row do
    %{"in_use_count" => 4, "total_count" => 6, "last_changed_at" => "2026-07-30T09:15:00"}
  end

  defp configuration_pg_query(row \\ configuration_row()) do
    fn _sql, _opts -> {:ok, %{"rows" => [row]}} end
  end

  describe "measure/2" do
    test "aggregates every catalog feature and parses counts and timestamps" do
      ch_query = fn _sql, _opts -> {:ok, %{"rows" => [grouped_row()]}} end

      assert {:ok, metrics} =
               Collector.measure(%{account_id: 42, project_ids: [1, 2]},
                 ch_query: ch_query,
                 pg_query: configuration_pg_query()
               )

      assert length(metrics) == length(Catalog.tracked())

      # Single-source feature: parsed straight through.
      selective = Enum.find(metrics, &(&1.feature == "selective_testing"))
      assert selective.events_last_24h == 3
      assert selective.events_last_7d == 10
      # prior-7d is not scanned (day-over-day churn), always zero
      assert selective.events_prior_7d == 0
      assert selective.last_used_at == ~U[2026-07-29 08:30:00Z]

      # Multi-source feature (command_events cache + module_cache): summed.
      cache = Enum.find(metrics, &(&1.feature == "cache"))
      assert cache.events_last_7d == 20
    end

    test "reports zeroes for project-scoped features when the account has no projects" do
      parent = self()

      ch_query = fn sql, opts ->
        send(parent, {:ch, sql, opts})
        {:ok, %{"rows" => [grouped_row()]}}
      end

      pg_query = fn sql, _opts ->
        assert sql =~ "FROM organizations o INNER JOIN accounts a ON a.organization_id = o.id"
        {:ok, %{"rows" => [%{"in_use_count" => 0, "total_count" => 0, "last_changed_at" => nil}]}}
      end

      assert {:ok, metrics} =
               Collector.measure(%{account_id: 42, project_ids: []}, ch_query: ch_query, pg_query: pg_query)

      cache = Enum.find(metrics, &(&1.feature == "cache"))
      assert cache.events_last_7d == 0
      assert cache.last_used_at == nil

      automations = Enum.find(metrics, &(&1.feature == "automations"))
      assert automations.events_last_7d == 0
      assert automations.events_last_24h == 0

      single_sign_on = Enum.find(metrics, &(&1.feature == "single_sign_on"))
      assert single_sign_on.events_last_7d == 0
      assert single_sign_on.events_last_24h == 0

      # Account-id groups still run, including single sign-on; project-scoped
      # configuration and ClickHouse groups are skipped entirely.
      queries = collect_queries([])
      assert queries != []
      refute Enum.any?(queries, fn {sql, _opts} -> sql =~ "project_id IN" end)
    end

    test "counts configuration features through the Postgres proxy" do
      parent = self()

      pg_query = fn sql, opts ->
        send(parent, {:pg, sql, opts})
        {:ok, %{"rows" => [configuration_row()]}}
      end

      assert {:ok, metrics} =
               Collector.measure(%{account_id: 42, project_ids: [1, 2]},
                 ch_query: fn _sql, _opts -> {:ok, %{"rows" => [grouped_row()]}} end,
                 pg_query: pg_query
               )

      automations = Enum.find(metrics, &(&1.feature == "automations"))
      # Enabled rows drive `active`; the total includes rows that are turned off.
      assert automations.events_last_7d == 4
      assert automations.events_last_24h == 6
      assert automations.events_prior_7d == 0
      assert automations.last_used_at == ~U[2026-07-30 09:15:00Z]

      assert_receive {:pg, sql, _opts}
      assert sql =~ "FROM automation_alerts"
      assert sql =~ "project_id IN (1, 2)"
      assert sql =~ "FILTER (WHERE enabled)"
    end

    test "detects single sign-on configured for the account" do
      parent = self()

      pg_query = fn sql, opts ->
        send(parent, {:pg, sql, opts})

        row =
          if sql =~ "organizations o INNER JOIN accounts a" do
            %{"in_use_count" => 1, "total_count" => 1, "last_changed_at" => "2026-07-31T10:45:00"}
          else
            configuration_row()
          end

        {:ok, %{"rows" => [row]}}
      end

      assert {:ok, metrics} =
               Collector.measure(%{account_id: 42, project_ids: [1, 2]},
                 ch_query: fn _sql, _opts -> {:ok, %{"rows" => [grouped_row()]}} end,
                 pg_query: pg_query
               )

      single_sign_on = Enum.find(metrics, &(&1.feature == "single_sign_on"))

      assert single_sign_on.events_last_7d == 1
      assert single_sign_on.events_last_24h == 1
      assert single_sign_on.last_used_at == ~U[2026-07-31 10:45:00Z]

      queries = collect_postgres_queries([])

      assert Enum.any?(queries, fn {sql, _opts} ->
               sql =~ "FROM organizations o INNER JOIN accounts a ON a.organization_id = o.id" and
                 sql =~ "a.id = 42" and
                 sql =~ "FILTER (WHERE o.sso_provider IS NOT NULL)"
             end)
    end

    test "detects continuous-integration providers from build and test telemetry" do
      parent = self()

      ch_query = fn sql, opts ->
        send(parent, {:ch, sql, opts})
        {:ok, %{"rows" => [grouped_row()]}}
      end

      assert {:ok, metrics} =
               Collector.measure(%{account_id: 42, project_ids: [1, 2]},
                 ch_query: ch_query,
                 pg_query: configuration_pg_query()
               )

      github = Enum.find(metrics, &(&1.feature == "continuous_integration_github"))
      assert github.events_last_7d == 20

      queries = collect_queries([])

      # Providers share the existing build/test table groups, so adding all of
      # them does not add scans. Each table still produces one aggregate query.
      build_queries = Enum.filter(queries, fn {sql, _opts} -> sql =~ "FROM build_runs" end)
      test_queries = Enum.filter(queries, fn {sql, _opts} -> sql =~ "FROM test_runs" end)

      assert [{build_sql, build_opts}] = build_queries
      assert [{test_sql, test_opts}] = test_queries
      assert build_opts[:params] == %{"account_id" => 42}
      assert test_opts[:params] == %{"account_id" => 42}

      for provider <- ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"] do
        assert build_sql =~ "ci_provider = '#{provider}'"
        assert test_sql =~ "ci_provider = '#{provider}'"
      end

      assert build_sql =~ "account_id = {account_id:Int64}"
      assert test_sql =~ "account_id = {account_id:Int64}"
    end

    test "fails the batch when the configuration query errors" do
      assert {:error, "boom"} =
               Collector.measure(%{account_id: 42, project_ids: [1]},
                 ch_query: fn _sql, _opts -> {:ok, %{"rows" => [grouped_row()]}} end,
                 pg_query: fn _sql, _opts -> {:error, "boom"} end
               )
    end

    test "collects Model Context Protocol usage from Grafana Loki by account handle" do
      parent = self()

      loki_query = fn "acme" ->
        send(parent, :loki_queried)

        {:ok,
         %{
           events_last_24h: 2,
           events_last_7d: 9,
           events_prior_7d: 0,
           last_used_at: ~U[2026-08-26 09:30:00Z]
         }}
      end

      assert {:ok, metrics} =
               Collector.measure(%{account_handle: "acme", account_id: 42, project_ids: [1, 2]},
                 ch_query: fn _sql, _opts -> {:ok, %{"rows" => [grouped_row()]}} end,
                 pg_query: configuration_pg_query(),
                 loki_query: loki_query
               )

      usage = Enum.find(metrics, &(&1.feature == "model_context_protocol"))
      assert usage.events_last_24h == 2
      assert usage.events_last_7d == 9
      assert usage.last_used_at == ~U[2026-08-26 09:30:00Z]
      assert_received :loki_queried
    end
  end

  defp collect_queries(acc) do
    receive do
      {:ch, sql, opts} -> collect_queries([{sql, opts} | acc])
    after
      0 -> acc
    end
  end

  defp collect_postgres_queries(acc) do
    receive do
      {:pg, sql, opts} -> collect_postgres_queries([{sql, opts} | acc])
    after
      0 -> acc
    end
  end
end
