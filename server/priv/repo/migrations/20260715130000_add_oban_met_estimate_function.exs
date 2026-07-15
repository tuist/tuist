defmodule Tuist.Repo.Migrations.AddObanMetEstimateFunction do
  use Ecto.Migration

  def up, do: Oban.Met.Migration.up()

  def down, do: Oban.Met.Migration.down()
end
