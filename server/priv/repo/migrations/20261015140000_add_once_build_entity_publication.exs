defmodule Tuist.Repo.Migrations.AddOnceBuildEntityPublication do
  use Ecto.Migration

  def change do
    alter table(:once_runs) do
      add :build_entities_published_at, :timestamptz
    end
  end
end
