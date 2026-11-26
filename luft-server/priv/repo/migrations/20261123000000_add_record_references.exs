defmodule LuftServer.Repo.Migrations.AddRecordReferences do
  use Ecto.Migration

  def change do
    alter table(:thread_messages) do
      add :record_reference, :map
    end
  end
end
