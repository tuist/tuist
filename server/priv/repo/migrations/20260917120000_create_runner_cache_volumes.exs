defmodule Tuist.Repo.Migrations.CreateRunnerCacheVolumes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:runner_cache_volumes, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:account_id, references(:accounts, on_delete: :delete_all), null: false)
      add(:repository_id, :bigint, null: false)
      add(:repository, :text, null: false)
      add(:key, :text, null: false)
      add(:architecture, :text, null: false)
      add(:uid, :integer, null: false)
      add(:generation, :integer, null: false, default: 1)
      add(:head_id, :uuid)
      add(:last_used_at, :timestamptz)
      add(:deleted_at, :timestamptz)
      timestamps(type: :timestamptz)
    end

    create(
      unique_index(
        :runner_cache_volumes,
        [:account_id, :repository_id, :key, :architecture, :uid],
        name: :runner_cache_volumes_identity
      )
    )

    create(index(:runner_cache_volumes, [:account_id, :last_used_at]))

    create table(:runner_cache_volume_uses, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(:volume_id, references(:runner_cache_volumes, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:generation, :integer, null: false)
      add(:parent_id, :uuid)
      add(:workflow_job_id, :bigint, null: false)
      add(:workflow_run_id, :bigint, null: false)
      add(:pod_name, :text, null: false)
      add(:pod_uid, :text, null: false)
      add(:node_name, :text, null: false)
      add(:can_publish, :boolean, null: false)
      add(:status, :text, null: false, default: "allocated")
      add(:warm, :boolean)
      add(:size_bytes, :bigint)
      add(:capacity_bytes, :bigint)
      add(:attach_ms, :bigint)
      add(:last_reported_at, :timestamptz)
      add(:attached_at, :timestamptz)
      add(:finished_at, :timestamptz)
      add(:deleted_at, :timestamptz)
      timestamps(type: :timestamptz)
    end

    create(unique_index(:runner_cache_volume_uses, [:volume_id, :generation, :pod_uid]))
    create(index(:runner_cache_volume_uses, [:volume_id, :inserted_at]))
    create(index(:runner_cache_volume_uses, [:node_name, :deleted_at]))
    create(index(:runner_cache_volume_uses, [:parent_id]))
  end
end
