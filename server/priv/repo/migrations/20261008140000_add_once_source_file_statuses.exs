defmodule Tuist.Repo.Migrations.AddOnceSourceFileStatuses do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :source_file_statuses, {:array, :integer}
    end
  end
end
