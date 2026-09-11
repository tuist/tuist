defmodule Tuist.Repo.Migrations.DropKuraRolloutServerOutboxColumns do
  use Ecto.Migration

  # The Kura rollout gate no longer judges replication outbox depth: the push
  # path that produced it was removed from the runtime, so the columns only
  # ever held zeros from the last release on. Nothing reads them any more.
  def change do
    alter table(:kura_rollout_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :baseline_outbox_messages, :bigint
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :outbox_peak, :bigint
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :outbox_low_water, :bigint
    end
  end
end
