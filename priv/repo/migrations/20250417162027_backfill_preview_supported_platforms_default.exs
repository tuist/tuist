defmodule Tuist.Repo.Migrations.BackfillPreviewSupportedPlatformsDefault do
  use Ecto.Migration
  import Ecto.Query
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    from(p in "previews",
      where: is_nil(p.supported_platforms),
      update: [set: [supported_platforms: []]]
    )
    |> repo().update_all([])
  end

  def down, do: :ok
end
