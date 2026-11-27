defmodule Tuist.Repo.Migrations.RaiseAirMacosRunnerConcurrencyDefaults do
  @moduledoc false
  use Ecto.Migration

  # Air's macOS runner default rose from 8 vCPU / 24 GB (one baseline guest)
  # to 16 vCPU / 48 GB: with one guest, parallel macOS jobs ran one after the
  # other, and the 16 vCPU / 48 GB shape could never start. Linux stays at
  # 16 vCPU / 64 GB. New accounts get the new values through the trigger;
  # existing macOS limits below them are raised for accounts without a live
  # Pro or Enterprise subscription (paid accounts are already above them).
  # Like every grant, nothing is lowered, and the change is recorded in the
  # limit history with source `plan`.
  #
  # Values are inlined rather than read from `Tuist.Runners.Concurrency`:
  # migrations must not depend on runtime code.

  @reason "air plan defaults (migration 20261127120000)"

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(16, 64, 16, 48))

    # Recorded in the limit history by its trigger, scoped to this transaction.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "SELECT set_config('tuist.runner_concurrency_source', 'plan', true), set_config('tuist.runner_concurrency_reason', '#{@reason}', true)"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(raise_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "SELECT set_config('tuist.runner_concurrency_source', '', true), set_config('tuist.runner_concurrency_reason', '', true)"
    )
  end

  # Forward-only for existing limits: lowering would take capacity away from
  # accounts that may already rely on it. New accounts start on the previous
  # default again.
  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(16, 64, 8, 24))
  end

  def raise_statement do
    """
    UPDATE runner_concurrency_limits l
       SET vcpus = GREATEST(l.vcpus, 16),
           memory_gb = GREATEST(l.memory_gb, 48),
           updated_at = NOW()
     WHERE l.platform = 'macos'
       AND (l.vcpus < 16 OR l.memory_gb < 48)
       AND NOT EXISTS (
         SELECT 1 FROM subscriptions s
          WHERE s.account_id = l.account_id
            AND s.status IN ('active', 'trialing', 'past_due')
            AND s.plan IN (1, 3)
       )
    """
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
