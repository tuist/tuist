defmodule Tuist.Repo.Migrations.PinRunnerKuraStorageClaims do
  use Ecto.Migration

  # Runner caches rendered a fixed 50Gi before joining account sizing. Preserve
  # that budget until measured sizing changes it; applying the smaller plan
  # default during enrollment would evict warm content without a sizing decision.
  def up, do: pin_existing_claims!(repo())

  def pin_existing_claims!(repo) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo.query!("""
    UPDATE kura_servers
    SET storage_claim_size = '50Gi'
    WHERE region = 'scw-fr-par-runners'
      AND storage_claim_size IS NULL
      AND status NOT IN (3, 4, 7)
    """)
  end

  # Pins may have changed through sizing since enrollment. Keep them on rollback
  # so the old code continues rendering the budget each instance now holds.
  def down, do: :ok
end
