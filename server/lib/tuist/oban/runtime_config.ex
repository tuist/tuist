defmodule Tuist.Oban.RuntimeConfig do
  @moduledoc """
  Pure functions deriving Oban runtime config from pod role, deploy env,
  the `tuist_hosted?` flag, registry sync ownership, and self-hosted
  artifact-retention settings.

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
  alias Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredLegacyBuildArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeModuleCacheArtifactsWorker
  alias Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker

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
    {"* * * * *", Tuist.Kura.Reconciler},
    {"*/5 * * * *", Tuist.Kura.Workers.ExpiredRegistrationsWorker},
    {"*/5 * * * *", Tuist.Kura.Workers.StaleSelfHostedPeersWorker},
    {"* * * * *", Tuist.Runners.Workers.StaleClaimsWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedRunnersWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedStampedPodsWorker},
    {"* * * * *", Tuist.Runners.Workers.ExpireInteractiveSessionsWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.WebhookRedeliveryWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.StaleQueuedJobsWorker}
  ]

  @database_artifact_retention_resource_types [
    :app_previews,
    :build_archives,
    :run_artifacts,
    :test_attachments,
    :shard_bundles
  ]

  @schedule_expired_artifacts_cron {"30 2 * * *", ScheduleExpiredArtifactsWorker}
  @legacy_build_artifact_retention_cron {"0 4 * * *", DeleteExpiredLegacyBuildArtifactsWorker}

  @cache_artifact_retention_crons [
    {"0 3 * * *", DeleteExpiredXcodeCacheArtifactsWorker},
    {"15 3 * * *", DeleteExpiredXcodeModuleCacheArtifactsWorker},
    {"30 3 * * *", DeleteExpiredGradleCacheArtifactsWorker},
    {"45 3 * * *", DeleteExpiredCasCacheArtifactsWorker}
  ]

  @hosted_artifact_retention_crons [
                                     @schedule_expired_artifacts_cron,
                                     @legacy_build_artifact_retention_cron
                                   ] ++ @cache_artifact_retention_crons

  # Self-hosted retention workers read their window from the environment on every run.
  # The environment is what decides *whether* a cron is installed at boot; the days
  # themselves are never carried in the job args.
  @self_hosted_args %{"self_hosted" => true}

  @prod_like_envs [:prod, :stag, :can]

  @doc """
  Crontab for the given pod mode, deploy env, and hosted state.

  Options:

    * `:swift_registry_sync_enabled?` (default `true`) — whether this
      deployment owns the Swift registry mirror sync.
    * `:artifact_retention_days` (default `%{}`) — self-hosted retention
      windows, keyed by resource type.

  Empty for any non-`:web` pod. On `:web` + prod-like env, returns
  project-level crons (alerts, automations, per-project Slack reports,
  sharded-test cleanup) — Tuist-hosted deployments additionally get the
  internal Slack ops reports, account-usage rollup, Stripe metered-billing
  reconciliation, and plan-based artifact retention. Self-hosted deployments
  add only the artifact-retention jobs explicitly configured by resource type.
  Preview gets only the Swift registry sync cron when registry sync is
  enabled, regardless of hosted flag, so registry previews can exercise the
  same queue path without running production housekeeping.
  """
  def crontab(mode, env, tuist_hosted?, opts \\ []) do
    swift_registry_sync_enabled? = Keyword.get(opts, :swift_registry_sync_enabled?, true)
    artifact_retention_days = Keyword.get(opts, :artifact_retention_days, %{})

    cond do
      mode == :web and env == :preview ->
        if swift_registry_sync_enabled?, do: @preview_crons, else: []

      mode == :web and env in @prod_like_envs ->
        if tuist_hosted? do
          hosted_crons =
            if swift_registry_sync_enabled? do
              @hosted_only_crons ++ [@swift_registry_sync_cron]
            else
              @hosted_only_crons
            end

          hosted_crons ++ @hosted_artifact_retention_crons ++ @shared_crons
        else
          self_hosted_artifact_retention_crons(artifact_retention_days) ++ @shared_crons
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

  defp self_hosted_artifact_retention_crons(artifact_retention_days) do
    database_crons =
      if Enum.any?(@database_artifact_retention_resource_types, &Map.has_key?(artifact_retention_days, &1)) do
        [self_hosted_cron(@schedule_expired_artifacts_cron)]
      else
        []
      end

    legacy_build_crons =
      if Map.has_key?(artifact_retention_days, :build_archives) do
        [self_hosted_cron(@legacy_build_artifact_retention_cron)]
      else
        []
      end

    cache_crons =
      if Map.has_key?(artifact_retention_days, :cache_artifacts) do
        Enum.map(@cache_artifact_retention_crons, &self_hosted_cron/1)
      else
        []
      end

    database_crons ++ legacy_build_crons ++ cache_crons
  end

  defp self_hosted_cron({schedule, worker}), do: {schedule, worker, args: @self_hosted_args}
end
