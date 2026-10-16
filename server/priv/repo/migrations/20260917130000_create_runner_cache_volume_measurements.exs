defmodule Tuist.Repo.Migrations.CreateRunnerCacheVolumeMeasurements do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:runner_cache_volume_measurements) do
      add(:usage_id, references(:runner_cache_volume_uses, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:size_bytes, :bigint)
      add(:capacity_bytes, :bigint)
      add(:deleted, :boolean, null: false, default: false)
      add(:observed_at, :timestamptz, null: false)
    end

    create(
      index(:runner_cache_volume_measurements, [:usage_id, :observed_at], concurrently: true)
    )
  end
end
