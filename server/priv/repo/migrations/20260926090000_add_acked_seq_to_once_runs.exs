defmodule Tuist.Repo.Migrations.AddAckedSeqToOnceRuns do
  use Ecto.Migration

  # `once_runs` is introduced by the same unreleased change, so there is no
  # populated table to lock and no concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default

  def change do
    alter table(:once_runs) do
      # The highest contiguous sequence durably projected for this run.
      # Held in per-node ETS before, which answered 0 to a client that
      # reconnected onto another pod; the client rejects that regression as
      # a protocol violation and abandons the rest of the run.
      add :acked_seq, :bigint, default: 0, null: false
    end
  end
end
