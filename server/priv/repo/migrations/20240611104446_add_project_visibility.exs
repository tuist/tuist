defmodule Tuist.Repo.Migrations.AddProjectVisibility do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :visibility, :integer, default: 0, null: false
    end
  end
end
