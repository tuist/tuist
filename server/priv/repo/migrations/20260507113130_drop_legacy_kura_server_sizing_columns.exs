defmodule Tuist.Repo.Migrations.DropLegacyKuraServerSizingColumns do
  use Ecto.Migration

  def up do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :spec, :map
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :volume_size_gi, :integer
    end
  end

  def down do
    :ok
  end
end
