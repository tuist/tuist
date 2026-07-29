defmodule Tuist.IngestRepo.Migrations.NullableLifecycleTimestampsOnRunnerJobs do
  use Ecto.Migration

  # `claimed_at`, `started_at`, `completed_at` carried an epoch
  # sentinel (`toDateTime64(0, 6)`) to represent "not yet". The
  # sentinel cluttered every read path with `toUnixTimestamp64Milli(?) > 0`
  # guards and let unset values render as 1970-01-01 in the UI
  # when a guard was forgotten. Switch to `Nullable(DateTime64(6, 'UTC'))`
  # so "not yet" is just NULL and the type system carries it.
  #
  # `enqueued_at` stays non-null (set on every initial INSERT) and
  # `updated_at` is the RMT version column (must stay non-null).
  #
  # Two-step per column:
  #   1. MODIFY COLUMN to Nullable with DEFAULT NULL — existing
  #      epoch values are preserved as literal `1970-01-01 00:00:00`,
  #      not converted to NULL.
  #   2. ALTER UPDATE WHERE the column still holds the epoch
  #      sentinel — converts those leftover values to NULL.
  #
  # `ALTER UPDATE` is an async mutation; size of `runner_jobs` is
  # small (table is days old), so the mutation completes quickly.
  def up do
    Enum.each(~w[claimed_at started_at completed_at], fn col ->
      execute(
        "ALTER TABLE runner_jobs MODIFY COLUMN #{col} Nullable(DateTime64(6, 'UTC')) DEFAULT NULL"
      )

      execute("ALTER TABLE runner_jobs UPDATE #{col} = NULL WHERE #{col} = toDateTime64(0, 6)")
    end)
  end

  def down do
    Enum.each(~w[claimed_at started_at completed_at], fn col ->
      execute("ALTER TABLE runner_jobs UPDATE #{col} = toDateTime64(0, 6) WHERE #{col} IS NULL")

      execute(
        "ALTER TABLE runner_jobs MODIFY COLUMN #{col} DateTime64(6, 'UTC') DEFAULT toDateTime64(0, 6)"
      )
    end)
  end
end
