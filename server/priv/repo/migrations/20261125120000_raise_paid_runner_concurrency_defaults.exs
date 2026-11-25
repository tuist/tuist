defmodule Tuist.Repo.Migrations.RaisePaidRunnerConcurrencyDefaults do
  @moduledoc false
  use Ecto.Migration

  # The Pro and Enterprise runner defaults rose from 16 vCPU / 48 GB to
  # 48 vCPU / 144 GB on macOS (six baseline guests) and from 32 vCPU / 64 GB
  # to 64 vCPU / 128 GB on Linux. Accounts with a live paid subscription are
  # raised to them; like every grant, a resource already above its new
  # default is kept. The change is recorded in the limit history with source
  # `plan`, so automatic growth counts its weekly bound from it.
  #
  # New accounts start on Air through the trigger, which this leaves alone;
  # `Tuist.Billing` raises an account to the paid defaults when a live Pro or
  # Enterprise subscription arrives.
  #
  # Values are inlined rather than read from `Tuist.Runners.Concurrency`:
  # migrations must not depend on runtime code.

  @reason "paid plan defaults (migration 20261125120000)"

  def up do
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

  # Forward-only: lowering would take capacity away from accounts that may
  # already rely on it, and automatic growth may have built on top of it.
  def down, do: :ok

  def raise_statement do
    """
    UPDATE runner_concurrency_limits l
       SET vcpus = GREATEST(l.vcpus, d.vcpus),
           memory_gb = GREATEST(l.memory_gb, d.memory_gb),
           updated_at = NOW()
      FROM (VALUES ('linux', 64, 128), ('macos', 48, 144)) AS d(platform, vcpus, memory_gb)
     WHERE l.platform = d.platform
       AND (l.vcpus < d.vcpus OR l.memory_gb < d.memory_gb)
       AND EXISTS (
         SELECT 1 FROM subscriptions s
          WHERE s.account_id = l.account_id
            AND s.status IN ('active', 'trialing', 'past_due')
            AND s.plan IN (1, 3)
       )
    """
  end
end
