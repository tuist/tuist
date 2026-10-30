defmodule Tuist.Repo.Migrations.AddHitCountToKuraOriginRollups do
  use Ecto.Migration

  def change do
    alter table(:kura_origin_rollups) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :hit_count, :bigint, null: false, default: 0
    end
  end
end
