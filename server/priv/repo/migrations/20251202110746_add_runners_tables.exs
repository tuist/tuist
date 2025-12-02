defmodule Tuist.Repo.Migrations.AddRunnersTables do
  use Ecto.Migration

  def change do
    create table(:runner_hosts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :ip, :string, null: false
      add :ssh_port, :integer, null: false
      add :capacity, :integer, null: false
      add :status, :integer, null: false, default: 0
      add :chip_type, :integer, null: false
      add :ram_gb, :integer, null: false
      add :storage_gb, :integer, null: false
      add :last_heartbeat_at, :timestamptz
      add :github_runner_token, :binary

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_hosts, [:name])
    create unique_index(:runner_hosts, [:ip])
    create index(:runner_hosts, [:status])
    create index(:runner_hosts, [:last_heartbeat_at])

    create table(:runner_images, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :os_version, :string, null: false
      add :xcode_version, :string, null: false
      add :base_image_name, :string
      add :labels, {:array, :string}, default: []
      add :status, :integer, null: false, default: 0
      add :size_gb, :integer
      add :checksum, :string

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_images, [:name])
    create index(:runner_images, [:status])
    create index(:runner_images, [:os_version])
    create index(:runner_images, [:xcode_version])
    create index(:runner_images, [:labels], using: :gin)

    create table(:runner_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :github_job_id, :integer, null: false
      add :run_id, :integer, null: false
      add :org, :string, null: false
      add :repo, :string, null: false
      add :labels, {:array, :string}, default: []
      add :status, :integer, null: false, default: 0
      add :host_id, references(:runner_hosts, type: :uuid, on_delete: :nilify_all)
      add :vm_name, :string
      add :started_at, :timestamptz
      add :completed_at, :timestamptz
      add :organization_id, references(:runner_organizations, type: :uuid, on_delete: :nilify_all)
      add :github_workflow_url, :string
      add :github_runner_name, :string
      add :error_message, :string

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_jobs, [:github_job_id])
    create index(:runner_jobs, [:status])
    create index(:runner_jobs, [:org])
    create index(:runner_jobs, [:host_id])
    create index(:runner_jobs, [:organization_id])
    create index(:runner_jobs, [:run_id])
    create index(:runner_jobs, [:labels], using: :gin)

    create table(:runner_organizations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, :integer, null: false
      add :enabled, :boolean, default: false, null: false
      add :label_prefix, :string
      add :allowed_labels, {:array, :string}, default: []
      add :max_concurrent_jobs, :integer
      add :github_app_installation_id, :integer

      timestamps(type: :timestamptz)
    end

    create unique_index(:runner_organizations, [:account_id])
    create unique_index(:runner_organizations, [:github_app_installation_id])
    create index(:runner_organizations, [:enabled])
    create index(:runner_organizations, [:allowed_labels], using: :gin)
  end
end
