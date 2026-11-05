defmodule Tuist.Repo.Migrations.MoveRemoteExecutionLimitsToAccounts do
  use Ecto.Migration

  # Release the column DDL lock before scanning the constraints.
  @disable_ddl_transaction true

  def up do
    alter table(:accounts) do
      # PostgreSQL 16 stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :remote_execution_vcpus_limit, :integer, default: 16, null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :remote_execution_memory_gb_limit, :integer, default: 32, null: false
    end

    flush()

    # NOT VALID avoids a table scan under the DDL lock; validation follows separately.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_remote_execution_vcpus_limit_positive,
             check: "remote_execution_vcpus_limit > 0",
             validate: false
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_remote_execution_memory_gb_limit_positive,
             check: "remote_execution_memory_gb_limit > 0",
             validate: false
           )

    flush()
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE accounts VALIDATE CONSTRAINT accounts_remote_execution_vcpus_limit_positive"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE accounts VALIDATE CONSTRAINT accounts_remote_execution_memory_gb_limit_positive"

    # The image, CAS, executor endpoint and nodes now come from the deployment.
    # No account was ever configured: the flag stayed off everywhere.
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:remote_execution_settings)
  end

  def down do
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

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:remote_execution_settings, :remote_execution_concurrency_range,
             check: "max_concurrency >= 0 AND max_concurrency <= 128"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:remote_execution_settings, :remote_execution_warm_pool_range,
             check: "warm_pool_size >= 0 AND warm_pool_size <= 8"
           )

    alter table(:accounts) do
      # Roll back binaries first; only these new account settings are removed.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :remote_execution_vcpus_limit
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :remote_execution_memory_gb_limit
    end
  end
end
