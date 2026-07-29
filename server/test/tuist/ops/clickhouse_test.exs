defmodule Tuist.Ops.ClickHouseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Ops.ClickHouse
  alias Tuist.OpsClickHouseRepo

  setup :set_mimic_from_context

  test "runs parameterized queries with read and resource limits" do
    expect(OpsClickHouseRepo, :query, fn statement, params, options ->
      assert statement =~ "SELECT *"
      assert statement =~ "FROM ("
      assert statement =~ "project_id IN {project_ids:Array(Int64)}"
      assert statement =~ "LIMIT 3"
      assert params == %{"project_ids" => [10, 20]}

      assert options[:decode] == false
      assert options[:format] == "JSONCompact"
      assert options[:timeout] == 15_000

      settings = options[:settings]
      assert settings[:readonly] == 1
      assert settings[:max_execution_time] == 10
      assert settings[:max_threads] == 2
      assert settings[:max_result_rows] == 3
      assert settings[:max_result_bytes] == 5 * 1024 * 1024
      assert settings[:max_block_size] == 3
      assert settings[:result_overflow_mode] == "throw"

      {:ok,
       json_result(
         ["project_id", "runs"],
         [
           [10, 12],
           [20, 8],
           [30, 4]
         ]
       )}
    end)

    assert {:ok,
            %{
              columns: ["project_id", "runs"],
              rows: [
                %{"project_id" => 10, "runs" => 12},
                %{"project_id" => 20, "runs" => 8}
              ],
              num_rows: 2,
              truncated?: true
            }} =
             ClickHouse.execute(
               "SELECT project_id, count() AS runs FROM command_events WHERE project_id IN {project_ids:Array(Int64)} GROUP BY project_id",
               params: %{"project_ids" => [10, 20]},
               limit: 2
             )
  end

  test "rejects metadata statements" do
    assert {:error, "Only SELECT and WITH statements are allowed"} =
             ClickHouse.execute("SHOW TABLES")
  end

  test "rejects statements that can write before reaching ClickHouse" do
    assert {:error, error} = ClickHouse.execute("ALTER TABLE command_events DELETE WHERE 1")
    assert error =~ "Only SELECT"
  end

  test "rejects external and cluster table functions" do
    for statement <- [
          "SELECT * FROM url('http://169.254.169.254', 'CSV', 'value String')",
          "SELECT * FROM `s3`('https://bucket.example/file.csv')",
          "SELECT * FROM remote/**/('10.0.0.5', system, tables)",
          "SELECT * FROM executable('cat', 'TabSeparated', 'value String')",
          "SELECT '-- not a comment', s3('https://bucket.example/file.csv')"
        ] do
      assert {:error, "External and cluster table functions are not allowed"} =
               ClickHouse.execute(statement)
    end
  end

  test "ignores blocked tokens inside string literals" do
    statements = [
      "SELECT 'system.tables' AS value",
      "SELECT 's3(' AS value",
      "SELECT 'INTO OUTFILE result' AS value",
      "SELECT '-- not a comment' AS value, 'url(' AS function_name"
    ]

    expect(OpsClickHouseRepo, :query, length(statements), fn _statement, %{}, _options ->
      {:ok, json_result(["value"], [["allowed"]])}
    end)

    for statement <- statements do
      assert {:ok, %{rows: [%{"value" => "allowed"}]}} = ClickHouse.execute(statement)
    end
  end

  test "rejects direct system table access" do
    assert {:error, "System metadata tables are not available through the query endpoint"} =
             ClickHouse.execute("SELECT * FROM `system`.`query_log`")

    assert {:error, "System metadata tables are not available through the query endpoint"} =
             ClickHouse.execute("SELECT * FROM information_schema.tables")
  end

  test "allows internal table discovery queries" do
    expect(OpsClickHouseRepo, :query, fn statement, %{}, _options ->
      assert statement =~ "FROM system.tables"
      {:ok, json_result(["database", "name"], [["tuist", "command_events"]])}
    end)

    assert {:ok, [%{"database" => "tuist", "name" => "command_events"}]} =
             ClickHouse.list_table_overviews()
  end

  test "rejects output clauses that cannot be wrapped" do
    assert {:error, "FORMAT and INTO OUTFILE clauses are not supported"} =
             ClickHouse.execute("SELECT 1 FORMAT JSON")

    assert {:error, "FORMAT and INTO OUTFILE clauses are not supported"} =
             ClickHouse.execute("SELECT 1 INTO OUTFILE '/tmp/result'")
  end

  test "rejects non-object query parameters" do
    assert {:error, "Query parameters must be an object"} =
             ClickHouse.execute("SELECT 1", params: [project_id: 1])
  end

  test "reports unavailable connections without exposing transport details" do
    expect(OpsClickHouseRepo, :query, fn _statement, _params, _options ->
      raise DBConnection.ConnectionError, message: "connection unavailable"
    end)

    assert {:error, :unavailable} = ClickHouse.execute("SELECT 1")
  end

  test "does not expose ClickHouse query errors" do
    expect(OpsClickHouseRepo, :query, fn _statement, _params, _options ->
      {:error, RuntimeError.exception("secret query details")}
    end)

    assert {:error, :query_failed} = ClickHouse.execute("SELECT 1")
  end

  test "rejects oversized responses before decoding" do
    expect(OpsClickHouseRepo, :query, fn _statement, _params, _options ->
      {:ok, %{data: :binary.copy("a", 5 * 1024 * 1024 + 1)}}
    end)

    assert {:error, :result_too_large} = ClickHouse.execute("SELECT 1")
  end

  defp json_result(columns, rows) do
    metadata = Enum.map(columns, &%{"name" => &1, "type" => "String"})

    %{
      data:
        JSON.encode!(%{
          "meta" => metadata,
          "data" => rows,
          "rows" => length(rows)
        })
    }
  end
end
