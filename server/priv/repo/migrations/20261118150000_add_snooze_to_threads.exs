defmodule Tuist.Repo.Migrations.AddSnoozeToThreads do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      # Hidden from the owner's inbox until this time (`Tuist.Threads.snooze/4`).
      add :snoozed_until, :timestamptz
      # Hidden until the thread's run stops and needs its owner. A constant
      # default is metadata-only in PostgreSQL, so the table isn't rewritten.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :snoozed_until_needed, :boolean, null: false, default: false
    end
  end
end
