defmodule Tuist.Repo.Migrations.DropXcodeTables do
  use Ecto.Migration

  def change do
    if not Tuist.Environment.tuist_hosted?() || Tuist.Environment.test?() do
      :ok
    else
      # excellent_migrations:safety-assured-for-next-line table_dropped
      drop table(:xcode_targets)
      # excellent_migrations:safety-assured-for-next-line table_dropped
      drop table(:xcode_projects)
      # excellent_migrations:safety-assured-for-next-line table_dropped
      drop table(:xcode_graphs)
    end
  end
end
