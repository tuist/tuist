defmodule Tuist.Repo.Migrations.CreateKuraDeployments do
  use Ecto.Migration

  def change do
    create table(:kura_deployments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :cluster_id, :string, null: false
      add :image_tag, :string, null: false
      add :status, :integer, null: false, default: 0
      add :error_message, :text
      add :oban_job_id, :bigint
      add :started_at, :timestamptz
      add :finished_at, :timestamptz

      timestamps(type: :timestamptz)
    end
  end
end
