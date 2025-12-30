defmodule Tuist.Repo.Migrations.AddRanAtToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :ran_at, :timestamptz, null: true
    end
  end
end
