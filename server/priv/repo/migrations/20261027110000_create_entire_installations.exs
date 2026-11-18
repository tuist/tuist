defmodule Tuist.Repo.Migrations.CreateEntireInstallations do
  use Ecto.Migration

  def change do
    # Retain the original table names and any existing plugin data while the
    # Entire integration moves out of the CI context.
    create_if_not_exists table(:ci_install_requests, primary_key: false) do
      add :state, :string, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :expires_at, :timestamptz, null: false
    end

    create_if_not_exists table(:ci_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :remote_id, :string, null: false
      add :active, :boolean, null: false, default: true
      add :revision, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists unique_index(:ci_installations, [:remote_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists index(:ci_installations, [:account_id])

    create_if_not_exists table(:ci_deliveries, primary_key: false) do
      add :id, :string, primary_key: true
      add :jwt_id, :string, null: false
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists unique_index(:ci_deliveries, [:jwt_id])

    # Preserve already queued deliveries after the worker's module relocation.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "UPDATE oban_jobs SET worker = 'Tuist.Entire.Workers.DeliveryWorker' WHERE worker = 'Tuist.CI.Workers.DeliveryWorker'",
      "UPDATE oban_jobs SET worker = 'Tuist.CI.Workers.DeliveryWorker' WHERE worker = 'Tuist.Entire.Workers.DeliveryWorker'"
    )
  end
end
