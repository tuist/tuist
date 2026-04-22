defmodule Cache.SQLiteMaintenanceWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.SQLiteMaintenanceWorker

  setup :set_mimic_from_context

  test "vacuums the primary repo and runs bounded KV maintenance" do
    maintenance_timeout = Cache.Config.key_value_maintenance_busy_timeout_ms()
    repo_timeout = Cache.Config.repo_busy_timeout_ms(Cache.KeyValueRepo)

    expect(Cache.Repo, :query, fn "PRAGMA incremental_vacuum(128000)" -> {:ok, %{rows: []}} end)

    expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

    expect(Cache.KeyValueRepo, :query, fn query ->
      cond do
        query == "PRAGMA busy_timeout = #{maintenance_timeout}" -> {:ok, %{rows: []}}
        query == "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        query == "PRAGMA incremental_vacuum(25000)" -> {:ok, %{rows: []}}
        query == "PRAGMA busy_timeout = #{repo_timeout}" -> {:ok, %{rows: []}}
      end
    end)

    assert :ok = SQLiteMaintenanceWorker.perform(%{})
  end

  test "skips KV maintenance when SQLite is busy" do
    maintenance_timeout = Cache.Config.key_value_maintenance_busy_timeout_ms()
    repo_timeout = Cache.Config.repo_busy_timeout_ms(Cache.KeyValueRepo)

    expect(Cache.Repo, :query, fn "PRAGMA incremental_vacuum(128000)" -> {:ok, %{rows: []}} end)

    expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

    expect(Cache.KeyValueRepo, :query, fn query ->
      cond do
        query == "PRAGMA busy_timeout = #{maintenance_timeout}" -> {:ok, %{rows: []}}
        query == "PRAGMA wal_checkpoint(PASSIVE)" -> raise %Exqlite.Error{message: "Database busy"}
        query == "PRAGMA busy_timeout = #{repo_timeout}" -> {:ok, %{rows: []}}
      end
    end)

    assert :ok = SQLiteMaintenanceWorker.perform(%{})
  end
end
