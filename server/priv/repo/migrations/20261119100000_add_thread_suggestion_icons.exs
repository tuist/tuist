defmodule Tuist.Repo.Migrations.AddThreadSuggestionIcons do
  use Ecto.Migration

  def change do
    alter table(:thread_messages) do
      add :suggestion_icons, :map
    end
  end
end
