defmodule Tuist.Oban.RuntimeConfig do
  @moduledoc """
  Pure functions deriving Oban runtime config from pod role, deploy env,
  the `tuist_hosted?` flag, and self-hosted artifact-retention settings.

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
    {"* * * * *", Tuist.Runners.Workers.StaleClaimsWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedRunnersWorker},
    {"* * * * *", Tuist.Runners.Workers.OrphanedStampedPodsWorker},
    {"* * * * *", Tuist.Runners.Workers.ExpireInteractiveSessionsWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.WebhookRedeliveryWorker},
    {"*/5 * * * *", Tuist.Runners.Workers.StaleQueuedJobsWorker},
    # Cron fires on the :web leader; the resulting `:swift_registry_sync`
    # job is consumed by the swift-registry-sync pod
    # (`TUIST_MODE=swift_registry_sync`). Hosted-only because the
    # registry mirror is a hosted-only feature.
    @swift_registry_sync_cron
  ]

  @hosted_artifact_retention_crons [
    {"30 2 * * *", ScheduleExpiredArtifactsWorker},
    {"0 4 * * *", DeleteExpiredLegacyBuildArtifactsWorker},
    {"0 3 * * *", DeleteExpiredXcodeCacheArtifactsWorker},
    {"15 3 * * *", DeleteExpiredXcodeModuleCacheArtifactsWorker},
    {"30 3 * * *", DeleteExpiredGradleCacheArtifactsWorker},
    {"45 3 * * *", DeleteExpiredCasCacheArtifactsWorker}
  ]

  @database_artifact_retention_resource_types [
    :app_previews,
    :build_archives,
    :run_artifacts,
    :test_attachments,
    :shard_bundles
  ]

  @cache_artifact_retention_crons [
    {"0 3 * * *", DeleteExpiredXcodeCacheArtifactsWorker},
    {"15 3 * * *", DeleteExpiredXcodeModuleCacheArtifactsWorker},
    {"30 3 * * *", DeleteExpiredGradleCacheArtifactsWorker},
    {"45 3 * * *", DeleteExpiredCasCacheArtifactsWorker}
  ]

  @prod_like_envs [:prod, :stag, :can]

  @doc """
  Crontab for the given pod mode, deploy env, hosted state, and optional
  self-hosted artifact-retention windows.

  Empty for any non-`:web` pod. On `:web` + prod-like env, returns
  project-level crons (alerts, automations, per-project Slack reports,
  sharded-test cleanup) — Tuist-hosted deployments additionally get the
  internal Slack ops reports, account-usage rollup, Stripe metered-billing
  reconciliation, and plan-based artifact retention. Self-hosted deployments
  add only the artifact-retention jobs explicitly configured by resource type.
  Preview gets only the Swift registry sync cron, regardless of hosted flag,
  so registry previews can exercise the same queue path without running
  production housekeeping.
  """
  def crontab(mode, env, tuist_hosted?, artifact_retention_days \\ %{}) do
    cond do
      mode == :web and env == :preview ->
        @preview_crons

      mode == :web and env in @prod_like_envs ->
        if tuist_hosted? do
          @hosted_only_crons ++ @hosted_artifact_retention_crons ++ @shared_crons
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
    database_retention_days =
      artifact_retention_days
      |> Map.take(@database_artifact_retention_resource_types)
      |> Map.new(fn {resource_type, days} -> {Atom.to_string(resource_type), days} end)

    database_crons =
      if map_size(database_retention_days) == 0 do
        []
      else
        [
          {"30 2 * * *", ScheduleExpiredArtifactsWorker,
           args: %{"retention_days" => database_retention_days, "self_hosted" => true}}
        ]
      end

    legacy_build_crons =
      case Map.fetch(artifact_retention_days, :build_archives) do
        {:ok, days} ->
          [
            {"0 4 * * *", DeleteExpiredLegacyBuildArtifactsWorker,
             args: %{"retention_days" => days, "self_hosted" => true}}
          ]

        :error ->
          []
      end

    cache_crons =
      case Map.fetch(artifact_retention_days, :cache_artifacts) do
        {:ok, days} ->
          Enum.map(@cache_artifact_retention_crons, fn {schedule, worker} ->
            {schedule, worker, args: %{"retention_days" => days, "self_hosted" => true}}
          end)

        :error ->
          []
      end

    database_crons ++ legacy_build_crons ++ cache_crons
  end
end
