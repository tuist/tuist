defmodule Tuist.Oban.RuntimeConfig do
  @moduledoc """
  Pure functions deriving Oban runtime config from pod role, deploy env,
  and the `tuist_hosted?` flag.

  Lifted out of `config/runtime.exs` so they can be unit-tested against
  every value of `Tuist.Environment.modes/0`. Without this, a future
  denylist regression — like the one where the `:xcresult_processor` role
  shipped leader-eligible with an empty crontab and silently halted every
  cron job — would only surface when the next non-web role rolled out and
  an incident reproduced. The accompanying test asserts every non-web
  mode returned by `Tuist.Environment.modes/0` is leader-ineligible and
  has an empty crontab, so the gate stays an allowlist by construction.
  """

  alias Tuist.Registry.Swift.SyncWorker

  @shared_crons [
    {"@hourly", Tuist.Slack.Workers.ReportWorker},
    {"*/10 * * * *", Tuist.Alerts.Workers.AlertWorker},
    {"@hourly", Tuist.Tests.Workers.ExpireStaleTestRunsWorker},
    {"* * * * *", Tuist.Automations.Workers.AutomationScheduler},
    {"@daily", Tuist.Runners.Workers.PruneArchivedLogsWorker}
  ]

  @swift_registry_sync_cron {"*/10 * * * *", SyncWorker}
  @preview_crons [
    {"* * * * *", SyncWorker}
  ]

  @hosted_only_crons [
    {"0 10 * * 1-5", Tuist.Ops.DailySlackReportWorker},
    {"0 * * * 1-5", Tuist.Ops.HourlySlackReportWorker},
    {"@daily", Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker},
    {"@daily", Tuist.Billing.Workers.SyncStripeMetersWorker},
    {"30 2 * * *", Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker},
    {"0 3 * * *", Tuist.Storage.Workers.DeleteExpiredXcodeCacheArtifactsWorker},
    {"15 3 * * *", Tuist.Storage.Workers.DeleteExpiredXcodeModuleCacheArtifactsWorker},
    {"30 3 * * *", Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker},
    {"45 3 * * *", Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker},
    {"* * * * *", Tuist.Kura.Reconciler},
    {"*/5 * * * *", Tuist.Kura.Workers.ExpiredRegistrationsWorker},
    {"* * * * *", Tuist.Runners.Workers.StaleClaimsWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedRunnersWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedStampedPodsWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.WebhookRedeliveryWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.StaleQueuedJobsWorker},
    # Cron fires on the :web leader; the resulting `:swift_registry_sync`
    # job is consumed by the swift-registry-sync pod
    # (`TUIST_MODE=swift_registry_sync`). Hosted-only because the
    # registry mirror is a hosted-only feature.
    @swift_registry_sync_cron
  ]

  @prod_like_envs [:prod, :stag, :can]

  @doc """
  Crontab for the given pod mode, deploy env, and `tuist_hosted?` flag.

  Empty for any non-`:web` pod. On `:web` + prod-like env, returns
  project-level crons (alerts, automations, per-project Slack reports,
  sharded-test cleanup) — Tuist-hosted deployments additionally get the
  internal Slack ops reports, account-usage rollup, and Stripe
  metered-billing reconciler. Preview gets only the Swift registry sync
  cron so registry previews can exercise the same queue path without
  running production housekeeping.
  """
  def crontab(mode, env, tuist_hosted?) do
    cond do
      mode == :web and env == :preview and tuist_hosted? ->
        @preview_crons

      mode == :web and env in @prod_like_envs ->
        if tuist_hosted? do
          @hosted_only_crons ++ @shared_crons
        else
          @shared_crons
        end

      true ->
        []
    end
  end

  @doc """
  Whether a pod with the given mode may win the Oban peer election.

  Only `:web` may. Every other mode runs as the least-privilege
  `tuist_processor` Postgres role, which can't satisfy
  `Oban.Met.Reporter`'s leader-path `CREATE OR REPLACE FUNCTION` query
  (the role lacks `CREATE` on the schema) — Reporter would crash on
  every checkpoint. Non-`:web` pods also carry an empty crontab, so a
  non-web leader silently halts every scheduled job.
  """
  def peer_eligible?(:web), do: true
  def peer_eligible?(_), do: false
end
