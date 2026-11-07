defmodule Tuist.Repo.Migrations.CreateSandboxCommands do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:sandbox_commands, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :sandbox_id, references(:sandboxes, type: :uuid, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :command, :text, null: false
      add :cwd, :text
      add :stdin, :boolean, null: false, default: false
      add :status, :string, null: false, default: "running"
      add :exit_code, :integer
      add :deadline_at, :timestamptz, null: false
      add :finished_at, :timestamptz
      add :inserted_at, :timestamptz, null: false
      add :updated_at, :timestamptz, null: false
    end

    create index(:sandbox_commands, [:sandbox_id, :status], concurrently: true)
    create index(:sandbox_commands, [:account_id], concurrently: true)
  end
end
