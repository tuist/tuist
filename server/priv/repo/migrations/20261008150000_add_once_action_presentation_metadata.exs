defmodule Tuist.Repo.Migrations.AddOnceActionPresentationMetadata do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :presentation, :map
    end
  end
end
