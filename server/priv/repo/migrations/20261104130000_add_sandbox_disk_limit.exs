defmodule Tuist.Repo.Migrations.AddSandboxDiskLimit do
  use Ecto.Migration

  # Release the column DDL lock before scanning the constraint.
  @disable_ddl_transaction true

  def up do
    alter table(:accounts) do
      # PostgreSQL 16 stores constant defaults without rewriting existing rows.
      # 420 GB is 30 Orbs of the default shape (10 GB workspace and a 4 GB
      # memory image), the per-account on-node cap this quota replaces.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sandbox_disk_gb_limit, :integer, default: 420, null: false
    end

    flush()

    # NOT VALID avoids a table scan under the DDL lock; validation follows separately.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_sandbox_disk_gb_limit_positive,
             check: "sandbox_disk_gb_limit > 0",
             validate: false
           )

    flush()
    # Validate outside the DDL transaction so the scan allows ordinary writes.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE accounts VALIDATE CONSTRAINT accounts_sandbox_disk_gb_limit_positive"
  end

  def down do
    alter table(:accounts) do
      # Roll back binaries first; only this account setting is removed.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sandbox_disk_gb_limit
    end
  end
end
