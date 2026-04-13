defmodule Tuist.Repo.Migrations.CreateRunnerTables do
  use Ecto.Migration

  def change do
    create_query =
      "CREATE TYPE runner_provisioning_mode AS ENUM ('managed', 'self_hosted')"

    drop_query = "DROP TYPE runner_provisioning_mode"
    execute(create_query, drop_query)

    create_query =
      "CREATE TYPE runner_job_status AS ENUM ('queued', 'provisioning', 'in_progress', 'completed', 'failed', 'cancelled')"

    drop_query = "DROP TYPE runner_job_status"
    execute(create_query, drop_query)

    create table(:runner_configurations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :enabled, :boolean, default: false, null: false
      add :provisioning_mode, :runner_provisioning_mode, default: "managed", null: false
      add :orchard_controller_url, :string
      add :orchard_service_account_name, :string
      add :orchard_encrypted_service_account_token, :binary
      add :default_tart_image, :string, null: false
      add :max_concurrent_jobs, :integer, default: 5, null: false
      add :label_prefix, :string, default: "tuist-runner", null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_configurations, [:account_id])

    create table(:runner_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :runner_configuration_id,
          references(:runner_configurations, type: :uuid, on_delete: :delete_all), null: false

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :github_workflow_job_id, :bigint, null: false
      add :github_run_id, :bigint
      add :github_repository_full_name, :string, null: false
      add :status, :runner_job_status, default: "queued", null: false
      add :orchard_vm_name, :string
      add :runner_name, :string
      add :tart_image, :string
      add :labels, {:array, :string}, default: []
      add :conclusion, :string
      add :queued_at, :timestamptz
      add :started_at, :timestamptz
      add :completed_at, :timestamptz
      add :error_message, :text

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_jobs, [:github_workflow_job_id])
    create index(:runner_jobs, [:runner_configuration_id])
    create index(:runner_jobs, [:account_id])
    create index(:runner_jobs, [:status])
  end
end
