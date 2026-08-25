defmodule Tuist.Repo.Migrations.BackfillRunnerTrialsForCurrentUsers do
  @moduledoc """
  Puts every account that can use runners onto a runner trial.

  Runner usage has been metered but unbillable since the meters went in:
  no runner Price is configured, so no subscription carries a runner
  item and nothing can be charged. Filling a Price id in is what ends
  that, and it ends it for everyone at once.

  This makes the existing state explicit per account before that
  happens, so the accounts already relying on runners keep not being
  billed until someone deliberately cancels their trial. Without it,
  wiring the Price would start billing them for usage they began under
  the understanding that it was free.

  "Can use" is the `:runners` flag, not past usage. Both halves are
  needed and neither contains the other: an account can hold the flag
  without having run anything yet, and the flag is only required in
  canary and production so an environment that does not require it has
  no gates to read.

  Covering the flag holders here rather than leaving them to
  `Tuist.Runners.Trials.backfill_runner_trials/0` is deliberate. The
  chart applies the values and the server image in one release, so the
  runner Price goes live in the same moment this runs; anything left for
  an operator to run afterwards is unprotected in between.

  Idempotent: it only touches accounts with no trial recorded, so
  re-running it cannot restart a trial that was deliberately cancelled.

  Queries the tables by name rather than through the Ecto schemas, and
  does not call `Tuist.Runners.Trials.backfill_runner_trials/0`, so this
  keeps doing what it did the day it was written even after those
  change. Use that function to catch accounts that gain runner access
  after this has run.
  """
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  import Ecto.Query

  def up do
    ran_a_job = from(s in "runner_sessions", select: s.account_id, distinct: true)

    has_access =
      from(f in "feature_flags",
        where: f.flag_name == "runners" and f.gate_type == "actor" and f.enabled == true,
        select: f.target
      )

    from(a in "accounts",
      where: is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at),
      where:
        a.id in subquery(ran_a_job) or
          fragment("'account:' || ?", a.id) in subquery(has_access),
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
