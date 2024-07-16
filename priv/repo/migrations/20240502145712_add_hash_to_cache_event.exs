defmodule Tuist.Repo.Migrations.AddHashToCacheEvent do
  use Ecto.Migration

  def change do
    alter table(:cache_events) do
      add :hash, :string
    end
  end
end
