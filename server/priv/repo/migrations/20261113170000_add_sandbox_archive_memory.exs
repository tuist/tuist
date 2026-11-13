defmodule Tuist.Repo.Migrations.AddSandboxArchiveMemory do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      add :archive_memory, :map
    end
  end
end
