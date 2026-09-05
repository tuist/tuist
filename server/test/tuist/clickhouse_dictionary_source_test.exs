defmodule Tuist.ClickHouseDictionarySourceTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouseDictionarySource

  defmodule PasswordlessRepo do
    @moduledoc false
    def config, do: [hostname: "127.0.0.1", port: 8123, database: "tuist_test"]
  end

  defmodule AuthenticatedRepo do
    @moduledoc false
    def config, do: [username: "tuist", password: "s3cret", database: "tuist"]
  end

  defmodule QuotedCredentialsRepo do
    @moduledoc false
    def config, do: [username: "o'brien", password: "back\\slash'quote"]
  end

  defmodule BlankPasswordRepo do
    @moduledoc false
    def config, do: [username: "tuist"]
  end

  describe "local_query/2" do
    test "carries the credentials the repo itself connects with" do
      assert ClickHouseDictionarySource.local_query(AuthenticatedRepo, "SELECT id, project_id FROM command_events") ==
               "CLICKHOUSE(QUERY 'SELECT id, project_id FROM command_events' USER 'tuist' PASSWORD 's3cret')"
    end

    test "escapes quotes in the query so it stays a single literal" do
      assert ClickHouseDictionarySource.local_query(PasswordlessRepo, "SELECT id FROM t WHERE name = 'a'") ==
               "CLICKHOUSE(QUERY 'SELECT id FROM t WHERE name = \\'a\\'')"
    end
  end

  describe "local_table/2" do
    test "omits credentials when the repo authenticates with none" do
      assert ClickHouseDictionarySource.local_table(PasswordlessRepo, "test_cases") ==
               "CLICKHOUSE(TABLE 'test_cases')"
    end

    test "carries the credentials the repo itself connects with" do
      assert ClickHouseDictionarySource.local_table(AuthenticatedRepo, "test_cases") ==
               "CLICKHOUSE(TABLE 'test_cases' USER 'tuist' PASSWORD 's3cret')"
    end

    test "escapes quotes and backslashes so a password cannot break out of its literal" do
      assert ClickHouseDictionarySource.local_table(QuotedCredentialsRepo, "test_cases") ==
               "CLICKHOUSE(TABLE 'test_cases' USER 'o\\'brien' PASSWORD 'back\\\\slash\\'quote')"
    end

    test "sends an empty password for a user configured without one" do
      assert ClickHouseDictionarySource.local_table(BlankPasswordRepo, "test_cases") ==
               "CLICKHOUSE(TABLE 'test_cases' USER 'tuist' PASSWORD '')"
    end
  end
end
