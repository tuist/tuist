defmodule Tuist.ReleaseTest do
  use ExUnit.Case, async: true

  alias Tuist.Release

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

  defp occurrences(contents, pattern) do
    contents
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end
end
