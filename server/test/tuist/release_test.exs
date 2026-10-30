defmodule Tuist.ReleaseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Release

  describe "ops_clickhouse_reconciliation_queries/4" do
    test "resets privileges and converges the restricted role and user" do
      queries =
        Release.ops_clickhouse_reconciliation_queries(
          "tuist",
          "tuist_ops",
          "tuist_ops_readonly",
          String.duplicate("a", 64)
        )

      statements = Enum.map(queries, &elem(&1, 0))

      assert statements == [
               "CREATE ROLE IF NOT EXISTS `tuist_ops_readonly`",
               "REVOKE ALL ON *.* FROM `tuist_ops_readonly`",
               """
               ALTER ROLE `tuist_ops_readonly` SETTINGS
                 readonly = 2,
                 max_execution_time = 10 MIN 1 MAX 10,
                 max_memory_usage = 1073741824 MIN 1 MAX 1073741824,
                 max_rows_to_read = 100000000 MIN 1 MAX 100000000,
                 max_bytes_to_read = 5000000000 MIN 1 MAX 5000000000,
                 max_result_rows = 10001 MIN 1 MAX 10001,
                 max_result_bytes = 5242880 MIN 1 MAX 5242880,
                 max_block_size = 10001 MIN 1 MAX 10001,
                 max_threads = 2 MIN 1 MAX 2
               """,
               "GRANT SELECT ON `tuist`.* TO `tuist_ops_readonly`",
               "GRANT SELECT ON system.tables TO `tuist_ops_readonly`",
               "GRANT SELECT ON system.columns TO `tuist_ops_readonly`",
               "REVOKE SELECT ON `tuist`.grafana_query_log FROM `tuist_ops_readonly`",
               """
               CREATE USER IF NOT EXISTS `tuist_ops`
               IDENTIFIED WITH sha256_hash BY '#{String.duplicate("a", 64)}'
               """,
               """
               ALTER USER `tuist_ops`
               IDENTIFIED WITH sha256_hash BY '#{String.duplicate("a", 64)}'
               """,
               "REVOKE ALL ON *.* FROM `tuist_ops`",
               "GRANT `tuist_ops_readonly` TO `tuist_ops`",
               "ALTER USER `tuist_ops` DEFAULT ROLE `tuist_ops_readonly`"
             ]

      assert Enum.all?(queries, fn {_statement, params} -> params == [] end)
    end

    test "rejects identifiers that could change the access statements" do
      assert_raise RuntimeError, ~r/TUIST_OPS_CLICKHOUSE_USERNAME must be a valid ClickHouse identifier/, fn ->
        Release.ops_clickhouse_reconciliation_queries(
          "tuist",
          "tuist_ops; DROP USER default",
          "tuist_ops_readonly",
          String.duplicate("a", 64)
        )
      end
    end
  end

  describe "grafana_clickhouse_reconciliation_queries/4" do
    test "converges a bounded read-only role" do
      queries =
        Release.grafana_clickhouse_reconciliation_queries(
          "tuist",
          "tuist_grafana",
          "tuist_grafana_readonly",
          String.duplicate("b", 64)
        )

      statements = Enum.map(queries, &elem(&1, 0))

      assert statements == [
               "CREATE ROLE IF NOT EXISTS `tuist_grafana_readonly`",
               "REVOKE ALL ON *.* FROM `tuist_grafana_readonly`",
               """
               ALTER ROLE `tuist_grafana_readonly` SETTINGS
                 readonly = 2,
                 max_execution_time = 60 MIN 1 MAX 120,
                 max_memory_usage = 8589934592 MIN 1 MAX 8589934592,
                 max_threads = 8 MIN 1 MAX 8
               """,
               "GRANT SELECT ON `tuist`.* TO `tuist_grafana_readonly`",
               "GRANT SELECT ON system.tables TO `tuist_grafana_readonly`",
               "GRANT SELECT ON system.columns TO `tuist_grafana_readonly`",
               "GRANT SELECT ON system.query_log TO `tuist_grafana_readonly`",
               """
               CREATE USER IF NOT EXISTS `tuist_grafana`
               IDENTIFIED WITH sha256_hash BY '#{String.duplicate("b", 64)}'
               """,
               """
               ALTER USER `tuist_grafana`
               IDENTIFIED WITH sha256_hash BY '#{String.duplicate("b", 64)}'
               """,
               "REVOKE ALL ON *.* FROM `tuist_grafana`",
               "GRANT `tuist_grafana_readonly` TO `tuist_grafana`",
               "ALTER USER `tuist_grafana` DEFAULT ROLE `tuist_grafana_readonly`"
             ]
    end

    test "rejects identifiers that could change the access statements" do
      assert_raise RuntimeError, ~r/TUIST_GRAFANA_CLICKHOUSE_ROLE must be a valid ClickHouse identifier/, fn ->
        Release.grafana_clickhouse_reconciliation_queries(
          "tuist",
          "tuist_grafana",
          "tuist_grafana_readonly TO default",
          String.duplicate("b", 64)
        )
      end
    end
  end

  describe "grafana_query_log_view_statement/1" do
    test "reads every replica's recent initial queries with the definer's rights" do
      statement = Release.grafana_query_log_view_statement("tuist")

      assert statement =~ "CREATE OR REPLACE VIEW `tuist`.grafana_query_log"
      assert statement =~ "DEFINER = default SQL SECURITY DEFINER"
      assert statement =~ "FROM clusterAllReplicas('default', system.query_log)"
      assert statement =~ "WHERE event_time >= now() - INTERVAL 1 DAY"
    end

    test "rejects a database name that could change the statement" do
      assert_raise RuntimeError, ~r/ClickHouse database must be a valid ClickHouse identifier/, fn ->
        Release.grafana_query_log_view_statement("tuist.x AS SELECT 1; --")
      end
    end
  end

  describe "grafana_role_grant_statements/3" do
    # Columns are granted individually rather than by table, so parse them back
    # out and compare sets: the assertion is about which columns are reachable,
    # not how the statement is formatted.
    defp granted_columns(statements_or_sql, table_pattern) do
      ~r/GRANT SELECT \(([^)]*)\) ON #{table_pattern}\.(\w+)/
      |> Regex.scan(statements_or_sql)
      |> Map.new(fn [_, cols, table] ->
        {table, cols |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.sort()}
      end)
    end

    defp statements do
      Release.grafana_role_grant_statements(~s|"tuist_grafana_ro"|, ~s|"tuist"|, ~s|"public"|)
    end

    test "brackets the column grants with a reset and a future-table revoke" do
      [first | rest] = statements()

      assert first == ~s|REVOKE ALL ON ALL TABLES IN SCHEMA "public" FROM "tuist_grafana_ro"|
      assert Enum.at(rest, 0) == ~s|GRANT CONNECT ON DATABASE "tuist" TO "tuist_grafana_ro"|
      assert Enum.at(rest, 1) == ~s|GRANT USAGE ON SCHEMA "public" TO "tuist_grafana_ro"|

      assert List.last(rest) ==
               ~s|ALTER DEFAULT PRIVILEGES IN SCHEMA "public" REVOKE ALL ON TABLES FROM "tuist_grafana_ro"|
    end

    test "grants exactly the columns the dashboard and the alert rules read" do
      assert granted_columns(Enum.join(statements(), "\n"), ~s|"public"|) == %{
               "accounts" => Enum.sort(~w(id name billing_email organization_id)),
               "bundles" => Enum.sort(~w(project_id inserted_at git_ref)),
               "organizations" => Enum.sort(~w(id created_at)),
               "previews" => Enum.sort(~w(project_id inserted_at)),
               "projects" => Enum.sort(~w(id name account_id created_at build_system)),
               "roles" => Enum.sort(~w(id resource_id resource_type)),
               "runner_cache_volume_uses" => Enum.sort(~w(volume_id base_generation warm attached_at)),
               "runner_cache_volumes" => Enum.sort(~w(id key platform)),
               "subscriptions" => Enum.sort(~w(account_id status)),
               "users" => ["created_at"],
               "users_roles" => Enum.sort(~w(user_id role_id))
             }
    end

    test "never grants a column that holds a secret" do
      granted = statements() |> Enum.filter(&String.starts_with?(&1, "GRANT SELECT (")) |> Enum.join("\n")

      # These all live in tables the dashboard reads, which is why the role is
      # column-scoped instead of using pg_read_all_data like tuist_ops_ro.
      for secret <- ~w(encrypted_password reset_password_token confirmation_token unlock_token
                       s3_secret_access_key s3_access_key_id oauth2_encrypted_client_secret
                       slack_webhook_url default_payment_method current_sign_in_ip) do
        refute granted =~ secret
      end

      # `token` and `email` are bare columns on users; `projects` also has a
      # bare `token`. Word-boundary matters here: `accounts.billing_email` IS
      # granted on purpose (it's the billing contact the panels show), and
      # `reset_password_token` must not be what satisfies the `token` check.
      # `_` is a word character, so `\bemail\b` does not match `billing_email`.
      refute granted =~ ~r/\btoken\b/
      refute granted =~ ~r/\bemail\b/
    end

    test "keeps the CloudNativePG fallback grant list in sync" do
      sql =
        __DIR__
        |> Path.join("../../../infra/cnpg/tuist-grafana-ro-grants.sql")
        |> Path.expand()
        |> File.read!()

      assert granted_columns(sql, ~s|:"tuist_schema"|) == granted_columns(Enum.join(statements(), "\n"), ~s|"public"|)
    end
  end

  describe "processor_role_grant_statements/3" do
    test "grants the audited processor table surface" do
      role = ~s("tuist_processor")
      database = ~s("tuist")
      schema = ~s("public")

      assert Release.processor_role_grant_statements(role, database, schema) == [
               ~s(REVOKE ALL ON ALL TABLES IN SCHEMA "public" FROM "tuist_processor"),
               ~s|REVOKE ALL (compressed, state, error, updated_at) ON TABLE "public".bazel_profile_uploads FROM "tuist_processor"|,
               ~s|REVOKE ALL (account_id, event_name, project_id, refresh_before) ON TABLE "public".mcp_event_subscriptions FROM "tuist_processor"|,
               ~s(GRANT CONNECT ON DATABASE "tuist" TO "tuist_processor"),
               ~s(GRANT USAGE ON SCHEMA "public" TO "tuist_processor"),
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public".oban_jobs, "public".oban_peers, "public".test_case_run_flaky_corrections, "public".bazel_test_invocations, "public".bazel_test_results, "public".bazel_test_summaries TO "tuist_processor"),
               ~s(GRANT USAGE, SELECT ON SEQUENCE "public".oban_jobs_id_seq TO "tuist_processor"),
               ~s(GRANT SELECT ON TABLE "public".accounts, "public".projects, "public".automation_alerts, "public".webhook_endpoints, "public".feature_flags, "public".coverage_commits, "public".git_repositories, "public".git_refs, "public".git_commits TO "tuist_processor"),
               ~s|GRANT SELECT, UPDATE (compressed, state, error, updated_at) ON TABLE "public".bazel_profile_uploads TO "tuist_processor"|,
               ~s|GRANT SELECT (account_id, event_name, project_id, refresh_before) ON TABLE "public".mcp_event_subscriptions TO "tuist_processor"|,
               ~s(GRANT SELECT, INSERT ON TABLE "public".mcp_event_job_keys TO "tuist_processor")
             ]
    end

    test "keeps the CloudNativePG fallback grant list in sync" do
      sql =
        __DIR__
        |> Path.join("../../../infra/cnpg/tuist-processor-grants.sql")
        |> Path.expand()
        |> File.read!()

      expected_read_grant =
        ~s(GRANT SELECT ON TABLE :"tuist_schema".accounts, :"tuist_schema".projects, :"tuist_schema".automation_alerts, :"tuist_schema".webhook_endpoints, :"tuist_schema".feature_flags, :"tuist_schema".coverage_commits, :"tuist_schema".git_repositories, :"tuist_schema".git_refs, :"tuist_schema".git_commits TO tuist_processor;)

      assert occurrences(sql, expected_read_grant) == 1

      assert sql =~
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers, :"tuist_schema".test_case_run_flaky_corrections, :"tuist_schema".bazel_test_invocations, :"tuist_schema".bazel_test_results, :"tuist_schema".bazel_test_summaries TO tuist_processor;)

      assert sql =~ ~s(REVOKE ALL ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_processor;)

      assert sql =~
               ~s|REVOKE ALL (compressed, state, error, updated_at) ON TABLE :"tuist_schema".bazel_profile_uploads FROM tuist_processor;|

      assert sql =~
               ~s|GRANT SELECT, UPDATE (compressed, state, error, updated_at) ON TABLE :"tuist_schema".bazel_profile_uploads TO tuist_processor;|

      assert sql =~
               ~s|REVOKE ALL (account_id, event_name, project_id, refresh_before) ON TABLE :"tuist_schema".mcp_event_subscriptions FROM tuist_processor;|

      assert sql =~
               ~s|GRANT SELECT (account_id, event_name, project_id, refresh_before) ON TABLE :"tuist_schema".mcp_event_subscriptions TO tuist_processor;|

      assert sql =~ ~s(GRANT SELECT, INSERT ON TABLE :"tuist_schema".mcp_event_job_keys TO tuist_processor;)
    end
  end

  describe "swift_registry_sync_role_grant_statements/3" do
    test "grants only the Oban surface" do
      role = ~s("tuist_swift_registry_sync")
      database = ~s("tuist")
      schema = ~s("public")

      assert Release.swift_registry_sync_role_grant_statements(role, database, schema) == [
               ~s(REVOKE ALL ON ALL TABLES IN SCHEMA "public" FROM "tuist_swift_registry_sync"),
               ~s(GRANT CONNECT ON DATABASE "tuist" TO "tuist_swift_registry_sync"),
               ~s(GRANT USAGE ON SCHEMA "public" TO "tuist_swift_registry_sync"),
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public".oban_jobs, "public".oban_peers TO "tuist_swift_registry_sync"),
               ~s(GRANT USAGE, SELECT ON SEQUENCE "public".oban_jobs_id_seq TO "tuist_swift_registry_sync")
             ]
    end

    test "keeps the CloudNativePG fallback grant list in sync" do
      sql =
        __DIR__
        |> Path.join("../../../infra/cnpg/tuist-swift-registry-sync-grants.sql")
        |> Path.expand()
        |> File.read!()

      assert sql =~
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers TO tuist_swift_registry_sync;)

      assert sql =~ ~s(GRANT USAGE, SELECT ON SEQUENCE :"tuist_schema".oban_jobs_id_seq TO tuist_swift_registry_sync;)

      assert sql =~ ~s(REVOKE ALL ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_swift_registry_sync;)
    end
  end

  defp occurrences(contents, pattern) do
    contents
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end
end
