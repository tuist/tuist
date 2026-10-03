defmodule Atlas.Repo.Migrations.UpdateObanToV14 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14)
  end

  def down do
    Oban.Migration.down(version: 12)
  end
end
