defmodule Tuist.Repo.Migrations.AddPathToXcodeProjects do
  use Ecto.Migration

  def up do
    alter table(:xcode_projects) do
      add :path, :string, null: false
    end
  end

  def down do
    secrets = Tuist.Environment.decrypt_secrets()

    if !Tuist.Environment.clickhouse_configured?(secrets) || Tuist.Environment.test?() do
      alter table(:xcode_projects) do
        remove :path, :string
      end
    else
      # Table was dropped by later migration, nothing to rollback
      :ok
    end
  end
end
