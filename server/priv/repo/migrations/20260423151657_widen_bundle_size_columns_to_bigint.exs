defmodule Tuist.Repo.Migrations.WidenBundleSizeColumnsToBigint do
  use Ecto.Migration

  def up do
    # `ALTER COLUMN ... TYPE bigint` rewrites the table holding ACCESS
    # EXCLUSIVE for the entire rewrite duration. The artifacts table is
    # multi-million rows in production and the rewrite blows past Supabase's
    # default statement_timeout, killing the migration mid-flight. Drop the
    # timeout for this transaction so the rewrite can complete; the table
    # is already locked, so an extra few minutes don't change the blast
    # radius. lock_timeout stays at its default (0 / wait forever) since
    # the migration is gated to a single deployer.
    execute "SET LOCAL statement_timeout = 0"

    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :install_size, :bigint, null: false, from: {:integer, null: false}
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :download_size, :bigint, from: :integer
    end

    alter table(:artifacts) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :size, :bigint, null: false, from: {:integer, null: false}
    end
  end

  def down do
    execute "SET LOCAL statement_timeout = 0"

    alter table(:artifacts) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :size, :integer, null: false, from: {:bigint, null: false}
    end

    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :download_size, :integer, from: :bigint
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :install_size, :integer, null: false, from: {:bigint, null: false}
    end
  end
end
