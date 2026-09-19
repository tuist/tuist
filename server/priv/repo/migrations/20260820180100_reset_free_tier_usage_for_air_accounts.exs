defmodule Tuist.Repo.Migrations.ResetFreeTierUsageForAirAccounts do
  use Ecto.Migration

  # Starts every Air account's free-tier counter from the deploy, so no account
  # is blocked on the first day for usage it accrued while the cap was not
  # enforced. `plan` 2 is Air; an account with no active or trialing
  # subscription resolves to Air too.
  #
  # The persisted counter is zeroed alongside the timestamp because the gate
  # reads it directly. Setting only the timestamp would leave accounts already
  # over the threshold blocked until the next daily recomputation, which is the
  # opposite of what this reset is for. The timestamp is what makes the reset
  # survive that recomputation.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE accounts a
    SET free_tier_reset_at = now(),
        current_month_remote_cache_hits_count = 0
    WHERE COALESCE((
      SELECT s.plan
      FROM subscriptions s
      WHERE s.account_id = a.id
        AND s.status IN ('active', 'trialing')
      ORDER BY s.inserted_at DESC, s.id DESC
      LIMIT 1
    ), 2) = 2
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("UPDATE accounts SET free_tier_reset_at = NULL")
  end
end
