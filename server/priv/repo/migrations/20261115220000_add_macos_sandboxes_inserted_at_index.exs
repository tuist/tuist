defmodule Tuist.Repo.Migrations.AddMacosSandboxesInsertedAtIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # The warm macOS sandbox pools' scaling signals read the last 14 days of
    # macOS creates, a small slice of a table that is mostly Linux sandboxes.
    create index(:sandboxes, [:inserted_at],
             where: "platform = 'darwin'",
             name: :sandboxes_darwin_inserted_at_index,
             concurrently: true
           )
  end
end
