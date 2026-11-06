defmodule Atlas.Repo.Migrations.AddPersonalExecutionEnvironments do
  use Ecto.Migration

  def change do
    create table(:personal_environments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :oauth_client_id, :uuid, null: false
      add :name, :text, null: false
      add :enabled, :boolean, null: false, default: false
      add :terminal, :boolean, null: false, default: false
      add :display, :boolean, null: false, default: false
      add :projects, {:array, :map}, null: false, default: []
      add :version, :bigint, null: false, default: 1
      add :online_until, :timestamptz
      add :connection_id, :uuid
      timestamps(type: :timestamptz)
    end

    create index(:personal_environments, [:owner_id])

    alter table(:orbit_threads) do
      add :environment_id, references(:personal_environments, type: :uuid, on_delete: :nilify_all)
      add :environment_name, :text
      add :project_id, :uuid
      add :personal_environment_dispatched, :boolean, null: false, default: false
    end

    alter table(:orbit_runs) do
      add :environment_id, references(:personal_environments, type: :uuid, on_delete: :nilify_all)
      add :project_id, :uuid
    end

    alter table(:orbit_messages) do
      add :device_input, :binary
      add :device_output, :binary
    end

    create table(:environment_commands, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :environment_id,
          references(:personal_environments, type: :uuid, on_delete: :delete_all), null: false

      add :environment_version, :bigint, null: false
      add :thread_id, references(:orbit_threads, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:orbit_runs, type: :uuid, on_delete: :delete_all), null: false

      add :message_id, references(:orbit_messages, type: :uuid, on_delete: :delete_all),
        null: false

      add :tool, :text, null: false
      add :arguments, :binary, null: false
      add :digest, :text, null: false
      add :claim_token, :uuid
      add :status, :text, null: false, default: "queued"
      add :result, :binary
      add :expires_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:environment_commands, [:message_id])
    create index(:environment_commands, [:environment_id, :status, :expires_at])
    create index(:environment_commands, [:run_id])

    create constraint(:environment_commands, :supported_tool,
             check:
               "tool IN ('environment_list_directory', 'environment_read_file', 'environment_terminal')"
           )

    create constraint(:environment_commands, :supported_status,
             check:
               "status IN ('queued', 'claimed', 'settled', 'cancelled', 'unknown', 'expired')"
           )

    create constraint(:environment_commands, :claim_required,
             check: "status NOT IN ('claimed', 'settled', 'unknown') OR claim_token IS NOT NULL"
           )

    create constraint(:environment_commands, :settled_result,
             check: "(status = 'settled') = (result IS NOT NULL)"
           )
  end
end
