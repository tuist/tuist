defmodule Tuist.Ops.ClickHouseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.Ops.ClickHouse

  setup :set_mimic_from_context

  test "runs parameterized queries with read and resource limits" do
    expect(ClickHouseRepo, :query, fn statement, params, options ->
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
      assert settings[:max_block_size] == 3
      assert settings[:result_overflow_mode] == "break"

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

  test "does not wrap metadata statements" do
    expect(ClickHouseRepo, :query, fn statement, %{}, _options ->
      assert statement == "SHOW TABLES"
      {:ok, json_result(["name"], [["command_events"]])}
    end)

    assert {:ok, %{rows: [%{"name" => "command_events"}], truncated?: false}} =
             ClickHouse.execute("SHOW TABLES")
  end

  test "rejects statements that can write before reaching ClickHouse" do
    assert {:error, error} = ClickHouse.execute("ALTER TABLE command_events DELETE WHERE 1")
    assert error =~ "Only SELECT"
  end

  test "rejects non-object query parameters" do
    assert {:error, "Query parameters must be an object"} =
             ClickHouse.execute("SELECT 1", params: [project_id: 1])
  end

  test "reports unavailable connections without exposing transport details" do
    expect(ClickHouseRepo, :query, fn _statement, _params, _options ->
      raise DBConnection.ConnectionError, message: "connection unavailable"
    end)

    assert {:error, :unavailable} = ClickHouse.execute("SELECT 1")
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
