defmodule Tuist.Repo.Migrations.RemoveSandboxDiskLimit do
  use Ecto.Migration

  # The account sandbox disk quota is gone: node disk budgets bound sandbox
  # disk. Deploy only after every server runs a release without the
  # `sandbox_disk_gb_limit` schema field, since older releases still select it.
  def up do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :sandbox_disk_gb_limit
    end
  end

  def down do
    alter table(:accounts) do
      # PostgreSQL 16 stores constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :sandbox_disk_gb_limit, :integer, default: 420, null: false
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:accounts, :accounts_sandbox_disk_gb_limit_positive,
             check: "sandbox_disk_gb_limit > 0"
           )
  end
end
