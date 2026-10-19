defmodule Tuist.Repo.Migrations.AddSubscriptionPaymentGrace do
  use Ecto.Migration

  def up do
    alter table(:subscriptions) do
      add :past_due_since, :timestamptz
      add :stripe_event_created_at, :timestamptz
      add :payment_grace_expiry_notified_at, :timestamptz
    end

    # Existing customers were promised access while Stripe retries. Give them
    # the full notice period rather than inferring a historical failure date.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "UPDATE subscriptions SET past_due_since = date_trunc('second', NOW()) WHERE status = 'past_due'"
    )

    # Let the new workers roll out before asking them to announce the policy
    # and the concrete deadline to customers already overdue at deployment.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    INSERT INTO oban_jobs (state, queue, worker, args, max_attempts, inserted_at, scheduled_at)
    SELECT 'scheduled', 'default', 'Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker',
           jsonb_build_object('subscription_id', id, 'notice', 'policy'), 5,
           NOW() AT TIME ZONE 'UTC', (NOW() AT TIME ZONE 'UTC') + INTERVAL '1 hour'
    FROM subscriptions
    WHERE status = 'past_due' AND plan <> 2
    """)
  end

  def down do
    # Cancel pending workers before removing the fields they read on rollback.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DELETE FROM oban_jobs
    WHERE worker IN (
      'Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker',
      'Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker',
      'Tuist.Billing.Workers.PaymentGraceExpirySweepWorker'
    ) AND state IN ('available', 'scheduled', 'retryable')
    """)

    alter table(:subscriptions) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :payment_grace_expiry_notified_at
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stripe_event_created_at
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :past_due_since
    end
  end
end
