defmodule Cache.SQLiteMaintenanceWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.SQLiteMaintenanceWorker

  setup :set_mimic_from_context

  test "vacuums both SQLite repos" do
    expect(Cache.Repo, :query, fn "PRAGMA incremental_vacuum(128000)" -> {:ok, %{rows: []}} end)

    expect(Cache.KeyValueRepo, :query, fn "PRAGMA incremental_vacuum(128000)" ->
      {:ok, %{rows: []}}
    end)

    assert :ok = SQLiteMaintenanceWorker.perform(%{})
  end
end
