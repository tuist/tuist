defmodule Tuist.Repo.Migrations.DropXcodeTables do
  use Ecto.Migration

  def change do
    if Tuist.Environment.on_premise?() || Mix.env() == :test do
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
