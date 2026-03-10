defmodule Cache.SQLiteMaintenanceWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.SQLiteMaintenanceWorker

  setup :set_mimic_from_context

  test "vacuums the primary repo and runs bounded KV maintenance" do
    expect(Cache.Repo, :query, fn "PRAGMA incremental_vacuum(128000)" -> {:ok, %{rows: []}} end)

    expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

    expect(Cache.KeyValueRepo, :query, fn query ->
      case query do
        "PRAGMA busy_timeout = 0" -> {:ok, %{rows: []}}
        "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        "PRAGMA incremental_vacuum(1000)" -> {:ok, %{rows: []}}
        "PRAGMA busy_timeout = 30000" -> {:ok, %{rows: []}}
      end
    end)

    assert :ok = SQLiteMaintenanceWorker.perform(%{})
  end

  test "skips KV maintenance when SQLite is busy" do
    expect(Cache.Repo, :query, fn "PRAGMA incremental_vacuum(128000)" -> {:ok, %{rows: []}} end)

    expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

    expect(Cache.KeyValueRepo, :query, fn query ->
      case query do
        "PRAGMA busy_timeout = 0" -> {:ok, %{rows: []}}
        "PRAGMA wal_checkpoint(PASSIVE)" -> raise %Exqlite.Error{message: "database is locked"}
        "PRAGMA busy_timeout = 30000" -> {:ok, %{rows: []}}
      end
    end)

    assert :ok = SQLiteMaintenanceWorker.perform(%{})
  end
end
