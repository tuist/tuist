defmodule Tuist.Repo.Migrations.WidenBundleSizeColumnsToBigint do
  use Ecto.Migration

  def up do
    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :install_size, :bigint, null: false, from: {:integer, null: false}
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :download_size, :bigint, from: :integer
    end

    alter table(:artifacts) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :size, :bigint, null: false, from: {:integer, null: false}
    end
  end

  def down do
    alter table(:artifacts) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :size, :integer, null: false, from: {:bigint, null: false}
    end

    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :download_size, :integer, from: :bigint
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :install_size, :integer, null: false, from: {:bigint, null: false}
    end
  end
end
