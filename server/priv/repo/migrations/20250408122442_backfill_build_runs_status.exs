defmodule Tuist.Repo.Migrations.BackfillBuildRunsStatus do
  use Ecto.Migration
  import Ecto.Query
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    from(b in "build_runs",
      where: is_nil(b.status),
      update: [set: [status: 0]]
    )
    |> repo().update_all([])
  end

  def down, do: :ok
end
