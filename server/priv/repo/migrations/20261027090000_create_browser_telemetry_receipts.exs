defmodule Tuist.Repo.Migrations.CreateBrowserTelemetryReceipts do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:browser_telemetry_receipts, primary_key: false) do
      add :key, :binary, primary_key: true
      add :lease_id, :uuid, null: false
      add :expires_at, :timestamptz, null: false
      add :completed_at, :timestamptz
    end

    create index(:browser_telemetry_receipts, [:expires_at])
  end
end
