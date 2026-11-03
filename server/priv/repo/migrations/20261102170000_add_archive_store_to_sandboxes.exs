defmodule Tuist.Repo.Migrations.AddArchiveStoreToSandboxes do
  use Ecto.Migration

  # The in-rack store that holds an archived sandbox's object, by its storage
  # target ID. NULL means the account's own storage.
  def change do
    alter table(:sandboxes) do
      add :archive_store, :string
    end
  end
end
