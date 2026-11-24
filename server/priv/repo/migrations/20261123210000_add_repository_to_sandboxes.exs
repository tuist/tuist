defmodule Tuist.Repo.Migrations.AddRepositoryToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The github.com `owner/name` a Mac created through the account API
      # was prepared for (`ClaudeCodeSnapshots.mac_source/3`); counts as a
      # spawn of that repository's macOS snapshots.
      add :repository, :string
    end
  end
end
