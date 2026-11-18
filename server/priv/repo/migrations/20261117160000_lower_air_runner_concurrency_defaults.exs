defmodule Tuist.Repo.Migrations.LowerAirRunnerConcurrencyDefaults do
  @moduledoc false
  use Ecto.Migration

  # Air accounts never grow their runner limits, so they start lower than
  # the paid plans: one job of the largest Linux shape (16 vCPU / 64 GB) and
  # one baseline macOS guest (8 vCPU / 24 GB). New accounts have no
  # subscription, so the trigger inserts the Air values;
  # `Tuist.Billing` raises an account to its paid plan's defaults when a
  # live Pro or Enterprise subscription arrives.
  #
  # Existing accounts are lowered only when nothing suggests anyone relies
  # on the old values: no live Pro or Enterprise subscription, no runner
  # trial, the limit still exactly the old default, no runner session in
  # the last 30 days, and (for macOS) no profile on the larger shape, which
  # Air's limit could never admit. Everything else keeps its limits; an
  # operator can lower them by hand.
  #
  # Values are inlined rather than read from `Tuist.Runners.Concurrency`:
  # migrations must not depend on runtime code.

  @reason "air plan defaults (migration 20261117160000)"

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(16, 64, 8, 24))

    # Recorded in the limit history by its trigger, scoped to this transaction.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "SELECT set_config('tuist.runner_concurrency_source', 'plan', true), set_config('tuist.runner_concurrency_reason', '#{@reason}', true)"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(lower_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "SELECT set_config('tuist.runner_concurrency_source', '', true), set_config('tuist.runner_concurrency_reason', '', true)"
    )
  end

  def lower_statement do
    """
    UPDATE runner_concurrency_limits l
       SET vcpus = CASE l.platform WHEN 'linux' THEN 16 ELSE 8 END,
           memory_gb = CASE l.platform WHEN 'linux' THEN 64 ELSE 24 END,
           updated_at = NOW()
      FROM accounts a
     WHERE a.id = l.account_id
       AND ((l.platform = 'linux' AND l.vcpus = 32 AND l.memory_gb = 64)
         OR (l.platform = 'macos' AND l.vcpus = 16 AND l.memory_gb = 48))
       AND NOT (a.runner_trial_started_at IS NOT NULL AND a.runner_trial_ended_at IS NULL)
       AND NOT EXISTS (
         SELECT 1 FROM subscriptions s
          WHERE s.account_id = a.id
            AND s.status IN ('active', 'trialing', 'past_due')
            AND s.plan IN (1, 3)
       )
       AND NOT EXISTS (
         SELECT 1 FROM runner_sessions rs
          WHERE rs.account_id = a.id AND rs.started_at > NOW() - INTERVAL '30 days'
       )
       AND NOT (
         l.platform = 'macos' AND EXISTS (
           SELECT 1 FROM runner_profiles p
            WHERE p.account_id = a.id AND p.platform = 'macos' AND (p.vcpus > 8 OR p.memory_gb > 24)
         )
       )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(32, 64, 16, 48))

    # Restores only the rows this migration lowered that still hold its values.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_concurrency_limits l
       SET vcpus = CASE l.platform WHEN 'linux' THEN 32 ELSE 16 END,
           memory_gb = CASE l.platform WHEN 'linux' THEN 64 ELSE 48 END,
           updated_at = NOW()
     WHERE ((l.platform = 'linux' AND l.vcpus = 16 AND l.memory_gb = 64)
         OR (l.platform = 'macos' AND l.vcpus = 8 AND l.memory_gb = 24))
       AND EXISTS (
         SELECT 1 FROM runner_concurrency_history h
          WHERE h.account_id = l.account_id AND h.platform = l.platform AND h.reason = '#{@reason}'
       )
    """)
  end

  defp default_limits_function(linux_vcpus, linux_memory_gb, macos_vcpus, macos_memory_gb) do
    """
    CREATE OR REPLACE FUNCTION create_default_runner_concurrency_limits()
    RETURNS trigger AS $$
    BEGIN
      INSERT INTO runner_concurrency_limits
        (account_id, platform, vcpus, memory_gb, inserted_at, updated_at)
      VALUES
        (NEW.id, 'linux', #{linux_vcpus}, #{linux_memory_gb}, NOW(), NOW()),
        (NEW.id, 'macos', #{macos_vcpus}, #{macos_memory_gb}, NOW(), NOW())
      ON CONFLICT (account_id, platform) DO NOTHING;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
