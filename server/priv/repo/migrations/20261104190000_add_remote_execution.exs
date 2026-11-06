defmodule Tuist.Repo.Migrations.AddRemoteExecution do
  use Ecto.Migration

  def change do
    # Bound lock acquisition on the existing sandboxes table during rollout.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'"

    alter table(:sandboxes) do
      # PostgreSQL 16 records this constant default without rewriting rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :purpose, :string, null: false, default: "agent"
      add :execution_lease_expires_at, :timestamptz
    end

    create table(:remote_execution_settings, primary_key: false) do
      add :account_id, references(:accounts, on_delete: :delete_all), primary_key: true
      add :max_concurrency, :integer, null: false, default: 0
      add :warm_pool_size, :integer, null: false, default: 0
      add :node_names, {:array, :string}, null: false, default: []
      add :image_tag, :string, null: false
      add :cas_endpoint, :string, null: false
      add :executor_endpoint, :string, null: false
      timestamps(type: :timestamptz)
    end

    # The settings table is created empty in this transaction.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:remote_execution_settings, :remote_execution_concurrency_range,
             check: "max_concurrency >= 0 AND max_concurrency <= 128"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:remote_execution_settings, :remote_execution_warm_pool_range,
             check: "warm_pool_size >= 0 AND warm_pool_size <= 8"
           )
  end
end
