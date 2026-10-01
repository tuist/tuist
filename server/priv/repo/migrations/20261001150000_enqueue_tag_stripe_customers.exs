defmodule Tuist.Repo.Migrations.EnqueueTagStripeCustomers do
  use Ecto.Migration

  # Oban isn't running while migrations run, so the one-off backfill job is
  # enqueued by inserting its row. It's scheduled after the rollout so that pods
  # still running the previous release, which lack the worker, don't burn its
  # attempts. The worker no-ops where Stripe isn't configured.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO oban_jobs (state, worker, queue, args, scheduled_at)
    VALUES ('scheduled', 'Tuist.Billing.Workers.TagStripeCustomersWorker', 'default', '{}', now() + interval '1 hour')
    """
  end

  def down, do: :ok
end
