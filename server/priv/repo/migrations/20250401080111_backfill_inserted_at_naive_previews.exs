defmodule Tuist.Repo.Migrations.BackfillInsertedAtNaivePreviews do
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    from(p in "previews",
      update: [set: [inserted_at_naive: p.inserted_at]]
    )
    |> repo().update_all([])
  end

  def down, do: :ok
end
