defmodule Tuist.Repo.Migrations.CreateKuraDeployments do
  use Ecto.Migration

  def change do
    create table(:kura_deployments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id,
          references(:accounts, on_delete: :delete_all),
          null: false

      add :cluster_id, :string, null: false
      add :image_tag, :string, null: false
      add :status, :integer, null: false, default: 0
      add :error_message, :text
      add :requested_by_user_id, references(:users, on_delete: :nilify_all)
      add :oban_job_id, :bigint
      add :started_at, :timestamptz
      add :finished_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:kura_deployments, [:account_id])
    create index(:kura_deployments, [:account_id, :cluster_id])
    create index(:kura_deployments, [:status])
    create index(:kura_deployments, [:inserted_at])
  end
end
