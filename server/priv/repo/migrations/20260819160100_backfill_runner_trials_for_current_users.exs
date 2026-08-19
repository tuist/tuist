defmodule Tuist.Repo.Migrations.BackfillRunnerTrialsForCurrentUsers do
  @moduledoc """
  Puts every account that has already run a runner job onto a runner
  trial.

  Runner usage has been metered but unbillable since the meters went in:
  no runner Price is configured, so no subscription carries a runner
  item and nothing can be charged. Filling a Price id in is what ends
  that, and it ends it for everyone at once.

  This makes the existing state explicit per account before that
  happens, so the accounts already relying on runners keep not being
  billed until someone deliberately cancels their trial. Without it,
  wiring the Price would start billing them for usage they began under
  the understanding that it was free.

  Idempotent: it only touches accounts with no trial recorded, so
  re-running it cannot restart a trial that was deliberately cancelled.

  Queries the tables by name rather than through the Ecto schemas, and
  does not call `Tuist.Runners.Trials.backfill_current_runner_users/0`,
  so this keeps doing what it did the day it was written even after
  those change. Use that function, not this, to catch accounts that
  start using runners between now and a Price being wired up.
  """
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  import Ecto.Query

  def up do
    runner_account_ids = from(s in "runner_sessions", select: s.account_id, distinct: true)

    from(a in "accounts",
      where: is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at),
      where: a.id in subquery(runner_account_ids),
      update: [set: [runner_trial_started_at: ^DateTime.utc_now()]]
    )
    |> Tuist.Repo.update_all([])
  end

  def down do
    from(a in "accounts",
      where: is_nil(a.runner_trial_ended_at),
      update: [set: [runner_trial_started_at: nil]]
    )
    |> Tuist.Repo.update_all([])
  end
end
