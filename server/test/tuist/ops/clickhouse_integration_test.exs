defmodule Tuist.Ops.ClickHouseIntegrationTest do
  use ExUnit.Case, async: false

  alias Tuist.ClickHouseRepo
  alias Tuist.Ops.ClickHouse

  setup do
    ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)
    :ok
  end

  test "executes a typed, bounded query against ClickHouse" do
    assert {:ok,
            %{
              columns: ["number"],
              rows: [%{"number" => 0}, %{"number" => 1}],
              num_rows: 2,
              truncated?: true
            }} =
             ClickHouse.execute(
               "SELECT number FROM numbers({count:UInt64}) ORDER BY number",
               params: %{"count" => 5},
               limit: 2
             )
  end
end
