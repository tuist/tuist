# The table and its index are new in this transaction, so building the index
# blocks no existing readers or writes.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreateThreadParticipants do
  use Ecto.Migration

  def change do
    # People the owner, or another participant, looped into a thread by
    # mentioning them. They read it and prompt it on the owner's subscription.
    create table(:thread_participants, primary_key: false) do
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :added_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :timestamptz)
    end

    create index(:thread_participants, [:user_id])
    create index(:thread_participants, [:added_by_id])
  end
end
