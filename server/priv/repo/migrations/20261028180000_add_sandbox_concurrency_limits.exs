defmodule Tuist.Repo.Migrations.AddSandboxConcurrencyLimits do
  use Ecto.Migration

  # Release the column DDL lock before backfilling and scanning constraints.
  @disable_ddl_transaction true

  def up do
    alter table(:accounts) do
      # PostgreSQL 16 stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sandbox_vcpus_limit, :integer, default: 32, null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sandbox_memory_gb_limit, :integer, default: 64, null: false
    end

    flush()

    # Only accounts with customized Linux limits need a row update. No network
    # calls, table rewrite or long-lived DDL lock accompanies this backfill.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(backfill_statement())

    # NOT VALID avoids a table scan under the DDL lock; validation follows separately.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_sandbox_vcpus_limit_positive,
             check: "sandbox_vcpus_limit > 0",
             validate: false
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_sandbox_memory_gb_limit_positive,
             check: "sandbox_memory_gb_limit > 0",
             validate: false
           )

    flush()
    # Validate outside the DDL transaction so the scans allow ordinary writes.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE accounts VALIDATE CONSTRAINT accounts_sandbox_vcpus_limit_positive"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE accounts VALIDATE CONSTRAINT accounts_sandbox_memory_gb_limit_positive"
  end

  def down do
    alter table(:accounts) do
      # Roll back binaries first; only these new account settings are removed.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sandbox_vcpus_limit
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sandbox_memory_gb_limit
    end
  end

  def backfill_statement do
    """
    UPDATE accounts AS a
    SET sandbox_vcpus_limit = limits.vcpus,
        sandbox_memory_gb_limit = limits.memory_gb
    FROM runner_concurrency_limits AS limits
    WHERE limits.account_id = a.id AND limits.platform = 'linux'
      AND (a.sandbox_vcpus_limit != limits.vcpus OR a.sandbox_memory_gb_limit != limits.memory_gb)
    """
  end
end
