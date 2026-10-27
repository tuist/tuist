Code.require_file(
  Path.expand("../../../priv/ingest_repo/migrations/20261026120000_preserve_command_argument_boundaries.exs", __DIR__)
)

defmodule Tuist.IngestRepo.Migrations.PreserveCommandArgumentBoundariesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.PreserveCommandArgumentBoundaries

  @columns for replica <- ["replica-a", "replica-b"],
               {name, type} <- [{"command_arguments_array", "Array(String)"}, {"command_arguments_recorded", "Bool"}],
               do: [replica, name, type]

  setup do
    state =
      start_supervised!(
        {Agent, fn -> %{queries: [], clustered?: true, replicas: [["replica-a"], ["replica-b"]], columns: [@columns]} end}
      )

    stub(IngestRepo, :query!, fn sql ->
      Agent.get_and_update(state, fn state ->
        state = %{state | queries: state.queries ++ [sql]}

        cond do
          String.starts_with?(sql, "ALTER TABLE") ->
            {%{rows: []}, state}

          sql == "SELECT currentDatabase()" ->
            {%{rows: [["tuist_test"]]}, state}

          String.contains?(sql, "system.clusters") ->
            {%{rows: if(state.clustered?, do: [[1]], else: [])}, state}

          String.contains?(sql, "system.one") ->
            {%{rows: state.replicas}, state}

          String.contains?(sql, "system.columns") ->
            [rows | rest] = state.columns
            {%{rows: rows}, %{state | columns: if(rest == [], do: [rows], else: rest)}}
        end
      end)
    end)

    %{state: state}
  end

  test "adds both columns before checking every replica", %{state: state} do
    assert :ok = PreserveCommandArgumentBoundaries.up()
    [alter | queries] = Agent.get(state, & &1.queries)
    assert alter =~ "ADD COLUMN IF NOT EXISTS command_arguments_array Array(String) DEFAULT []"
    assert alter =~ "ADD COLUMN IF NOT EXISTS command_arguments_recorded Bool DEFAULT false"
    assert Enum.any?(queries, &String.contains?(&1, "clusterAllReplicas(default, system.columns)"))
    refute Enum.any?(queries, &String.contains?(&1, "command_events_by_"))
  end

  test "waits for delayed schema replication", %{state: state} do
    Agent.update(state, &%{&1 | columns: [Enum.take(@columns, 2), @columns]})
    assert :ok = PreserveCommandArgumentBoundaries.verify_columns!(2_000)

    assert state |> Agent.get(& &1.queries) |> Enum.count(&String.contains?(&1, "system.columns")) == 2
  end

  test "fails when a replica is missing columns", %{state: state} do
    Agent.update(state, &%{&1 | columns: [Enum.take(@columns, 2)]})

    assert_raise Ecto.MigrationError, ~r/not ready on every ClickHouse replica.*replica-b/, fn ->
      PreserveCommandArgumentBoundaries.verify_columns!(0)
    end
  end

  test "fails on incompatible pre-existing column types", %{state: state} do
    columns = Enum.map(@columns, fn [replica, name, _type] -> [replica, name, "String"] end)
    Agent.update(state, &%{&1 | columns: [columns]})

    assert_raise Ecto.MigrationError, ~r/not ready on every ClickHouse replica/, fn ->
      PreserveCommandArgumentBoundaries.verify_columns!(0)
    end
  end

  test "uses local metadata only when the cluster is absent", %{state: state} do
    Agent.update(state, &%{&1 | clustered?: false, replicas: [["replica-a"]], columns: [Enum.take(@columns, 2)]})
    assert :ok = PreserveCommandArgumentBoundaries.verify_columns!(0)
    queries = Agent.get(state, & &1.queries)
    assert Enum.any?(queries, &String.contains?(&1, "FROM system.columns"))
    refute Enum.any?(queries, &String.contains?(&1, "clusterAllReplicas"))
  end

  test "does not fall back to local metadata on cluster errors" do
    expect(IngestRepo, :query!, fn "SELECT currentDatabase()" -> %{rows: [["tuist_test"]]} end)
    expect(IngestRepo, :query!, fn _sql -> raise "cluster unavailable" end)

    assert_raise RuntimeError, "cluster unavailable", fn ->
      PreserveCommandArgumentBoundaries.verify_columns!(0)
    end
  end

  test "rejects empty replica discovery", %{state: state} do
    Agent.update(state, &%{&1 | replicas: []})

    assert_raise Ecto.MigrationError, "ClickHouse replica discovery returned no replicas", fn ->
      PreserveCommandArgumentBoundaries.verify_columns!(0)
    end
  end

  test "rollback removes only the additive columns", %{state: state} do
    PreserveCommandArgumentBoundaries.down()
    assert [query] = Agent.get(state, & &1.queries)
    assert query =~ "DROP COLUMN IF EXISTS command_arguments_array"
    assert query =~ "DROP COLUMN IF EXISTS command_arguments_recorded"
    refute query =~ "DROP COLUMN IF EXISTS command_arguments,"
  end
end
