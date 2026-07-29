defmodule Tuist.ReleaseTest do
  use ExUnit.Case, async: true

  alias Tuist.Release

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

    test "grants exactly the columns the dashboard reads" do
      assert granted_columns(Enum.join(statements(), "\n"), ~s|"public"|) == %{
               "accounts" => Enum.sort(~w(id name billing_email organization_id current_month_remote_cache_hits_count
                    current_month_remote_cache_hits_count_updated_at)),
               "bundles" => Enum.sort(~w(project_id inserted_at git_ref)),
               "organizations" => Enum.sort(~w(id created_at)),
               "previews" => Enum.sort(~w(project_id inserted_at)),
               "projects" => Enum.sort(~w(id name account_id created_at build_system)),
               "roles" => Enum.sort(~w(id resource_id resource_type)),
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
               ~s(GRANT CONNECT ON DATABASE "tuist" TO "tuist_processor"),
               ~s(GRANT USAGE ON SCHEMA "public" TO "tuist_processor"),
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public".oban_jobs, "public".oban_peers TO "tuist_processor"),
               ~s(GRANT USAGE, SELECT ON SEQUENCE "public".oban_jobs_id_seq TO "tuist_processor"),
               ~s(GRANT SELECT ON TABLE "public".accounts, "public".projects, "public".automation_alerts, "public".webhook_endpoints TO "tuist_processor")
             ]
    end

    test "keeps the CloudNativePG fallback grant list in sync" do
      sql =
        __DIR__
        |> Path.join("../../../infra/cnpg/tuist-processor-grants.sql")
        |> Path.expand()
        |> File.read!()

      expected_read_grant =
        ~s(GRANT SELECT ON TABLE :"tuist_schema".accounts, :"tuist_schema".projects, :"tuist_schema".automation_alerts, :"tuist_schema".webhook_endpoints TO tuist_processor;)

      assert occurrences(sql, expected_read_grant) == 1

      assert sql =~
               ~s(GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers TO tuist_processor;)

      assert sql =~ ~s(REVOKE ALL ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_processor;)
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
