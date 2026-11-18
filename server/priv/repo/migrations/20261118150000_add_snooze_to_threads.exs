defmodule Tuist.Repo.Migrations.AddSnoozeToThreads do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      # Hidden from the owner's inbox until this time (`Tuist.Threads.snooze/4`).
      add :snoozed_until, :timestamptz
      # Hidden until the thread's run stops and needs its owner.
      add :snoozed_until_needed, :boolean, null: false, default: false
    end
  end
end
