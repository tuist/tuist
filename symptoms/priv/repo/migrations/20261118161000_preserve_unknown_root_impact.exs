defmodule Symptoms.Repo.Migrations.PreserveUnknownRootImpact do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:root_scores) do
      modify :impact, :float, null: true, default: nil
    end
  end

  def down do
    execute "UPDATE root_scores SET impact = 0 WHERE impact IS NULL"

    alter table(:root_scores) do
      modify :impact, :float, null: false, default: 0.0
    end
  end
end
