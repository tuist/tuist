defmodule Tuist.Oban.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker
  alias Tuist.Alerts.Workers.AlertWorker
  alias Tuist.Automations.Workers.AutomationScheduler
  alias Tuist.Billing.Workers.SyncStripeMetersWorker
  alias Tuist.Environment
  alias Tuist.Kura.Reconciler, as: KuraReconciler
  alias Tuist.Oban.RuntimeConfig
  alias Tuist.Ops.DailySlackReportWorker
  alias Tuist.Ops.HourlySlackReportWorker
  alias Tuist.Registry.Swift.SyncWorker
  alias Tuist.Runners.Workers.ExpireInteractiveSessionsWorker
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker
  alias Tuist.Runners.Workers.StaleQueuedJobsWorker
  alias Tuist.Slack.Workers.ReportWorker
  alias Tuist.Storage.Workers.DeleteExpiredCasCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredGradleCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredLegacyBuildArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeCacheArtifactsWorker
  alias Tuist.Storage.Workers.DeleteExpiredXcodeModuleCacheArtifactsWorker
  alias Tuist.Storage.Workers.ScheduleExpiredArtifactsWorker
  alias Tuist.Tests.Workers.ExpireStaleTestRunsWorker

  @cache_retention_workers [
    DeleteExpiredCasCacheArtifactsWorker,
    DeleteExpiredGradleCacheArtifactsWorker,
    DeleteExpiredXcodeCacheArtifactsWorker,
    DeleteExpiredXcodeModuleCacheArtifactsWorker
  ]

  describe "peer_eligible?/1" do
    test ":web is leader-eligible" do
      assert RuntimeConfig.peer_eligible?(:web)
    end

    test "every non-web mode is leader-ineligible" do
      for mode <- Environment.modes(), mode != :web do
        refute RuntimeConfig.peer_eligible?(mode),
               "expected #{inspect(mode)} to be leader-ineligible — " <>
                 "non-web pods run as least-privilege roles that crash Oban.Met.Reporter " <>
                 "and carry empty crontabs, so a non-web leader silently halts every scheduled job"
      end
    end
  end

  describe "crontab/4" do
    test "empty for every non-web mode in every prod-like env, regardless of hosted state" do
      for mode <- Environment.modes(),
          mode != :web,
          env <- [:prod, :stag, :can],
          tuist_hosted? <- [true, false],
          artifact_retention_days <- [%{}, %{cache_artifacts: 30, app_previews: 30}] do
        assert RuntimeConfig.crontab(mode, env, tuist_hosted?, artifact_retention_days) == [],
               "expected empty crontab for mode=#{inspect(mode)} env=#{inspect(env)} hosted=#{inspect(tuist_hosted?)}"
      end
    end

    test "empty for :web in non-prod-like envs, except previews" do
      for env <- [:dev, :test, :preview], tuist_hosted? <- [true, false] do
        if env == :preview do
          assert [{"* * * * *", SyncWorker}] =
                   RuntimeConfig.crontab(:web, env, tuist_hosted?, %{cache_artifacts: 30})
        else
          assert RuntimeConfig.crontab(:web, env, tuist_hosted?, %{cache_artifacts: 30}) == []
        end
      end
    end

    test ":web + preview only runs the Swift registry sync cron" do
      for tuist_hosted? <- [true, false] do
        assert RuntimeConfig.crontab(:web, :preview, tuist_hosted?, %{cache_artifacts: 30}) == [
                 {"* * * * *", SyncWorker}
               ]
      end

      for mode <- Environment.modes(), mode != :web do
        assert RuntimeConfig.crontab(mode, :preview, true, %{cache_artifacts: 30}) == []
      end
    end

    test ":web + non-preview non-prod-like envs stay empty" do
      for env <- [:dev, :test], tuist_hosted? <- [true, false] do
        assert RuntimeConfig.crontab(:web, env, tuist_hosted?, %{cache_artifacts: 30}) == []
      end
    end

    test ":web + prod-like env, self-hosted without retention configuration: shared crons only" do
      for env <- [:prod, :stag, :can] do
        workers =
          :web
          |> RuntimeConfig.crontab(env, false, %{})
          |> Enum.map(fn {_cron, worker} -> worker end)

        assert AutomationScheduler in workers
        assert AlertWorker in workers
        assert ReportWorker in workers
        assert ExpireStaleTestRunsWorker in workers
        assert PruneArchivedLogsWorker in workers

        refute ExpireInteractiveSessionsWorker in workers
        refute DailySlackReportWorker in workers
        refute HourlySlackReportWorker in workers
        refute UpdateAllAccountsUsageWorker in workers
        refute ScheduleExpiredArtifactsWorker in workers
        refute DeleteExpiredCasCacheArtifactsWorker in workers
        refute DeleteExpiredLegacyBuildArtifactsWorker in workers
        refute DeleteExpiredXcodeCacheArtifactsWorker in workers
        refute DeleteExpiredXcodeModuleCacheArtifactsWorker in workers
        refute DeleteExpiredGradleCacheArtifactsWorker in workers
        refute SyncStripeMetersWorker in workers
        refute KuraReconciler in workers
        refute StaleQueuedJobsWorker in workers
      end
    end

    test ":web + prod-like env, self-hosted: each configured family enables only its retention workers" do
      cases = [
        {%{cache_artifacts: 14},
         [
           DeleteExpiredCasCacheArtifactsWorker,
           DeleteExpiredGradleCacheArtifactsWorker,
           DeleteExpiredXcodeCacheArtifactsWorker,
           DeleteExpiredXcodeModuleCacheArtifactsWorker
         ]},
        {%{app_previews: 30}, [ScheduleExpiredArtifactsWorker]},
        {%{build_archives: 45}, [ScheduleExpiredArtifactsWorker, DeleteExpiredLegacyBuildArtifactsWorker]},
        {%{run_artifacts: 60}, [ScheduleExpiredArtifactsWorker]},
        {%{test_attachments: 75}, [ScheduleExpiredArtifactsWorker]},
        {%{shard_bundles: 90}, [ScheduleExpiredArtifactsWorker]}
      ]

      retention_workers = [
        ScheduleExpiredArtifactsWorker,
        DeleteExpiredCasCacheArtifactsWorker,
        DeleteExpiredGradleCacheArtifactsWorker,
        DeleteExpiredLegacyBuildArtifactsWorker,
        DeleteExpiredXcodeCacheArtifactsWorker,
        DeleteExpiredXcodeModuleCacheArtifactsWorker
      ]

      for {artifact_retention_days, expected_workers} <- cases do
        configured_workers =
          :web
          |> RuntimeConfig.crontab(:prod, false, artifact_retention_days)
          |> Enum.map(&cron_worker/1)
          |> Enum.filter(&(&1 in retention_workers))

        assert Enum.sort(configured_workers) == Enum.sort(expected_workers)
      end
    end

    test ":web + prod-like env, self-hosted: database-backed families share one scheduler" do
      artifact_retention_days = %{
        app_previews: 30,
        build_archives: 45,
        run_artifacts: 60,
        test_attachments: 75,
        shard_bundles: 90
      }

      crontab = RuntimeConfig.crontab(:web, :prod, false, artifact_retention_days)

      assert {"30 2 * * *", ScheduleExpiredArtifactsWorker, args: %{"self_hosted" => true}} in crontab

      assert Enum.count(crontab, &(cron_worker(&1) == ScheduleExpiredArtifactsWorker)) == 1

      assert {"0 4 * * *", DeleteExpiredLegacyBuildArtifactsWorker, args: %{"self_hosted" => true}} in crontab
    end

    test ":web + prod-like env, self-hosted: cron args carry no retention window" do
      artifact_retention_days = %{app_previews: 30, build_archives: 45, cache_artifacts: 21}

      for {_schedule, _worker, opts} <- RuntimeConfig.crontab(:web, :prod, false, artifact_retention_days) do
        refute Map.has_key?(opts[:args], "retention_days"),
               "self-hosted retention workers read their window from the environment on every " <>
                 "run, so a window in the job args is dead payload that shadows the real source"
      end
    end

    test ":web + prod-like env, self-hosted: cache retention configures all cache workers" do
      crontab = RuntimeConfig.crontab(:web, :prod, false, %{cache_artifacts: 21})

      assert {"0 3 * * *", DeleteExpiredXcodeCacheArtifactsWorker, args: %{"self_hosted" => true}} in crontab
      assert {"15 3 * * *", DeleteExpiredXcodeModuleCacheArtifactsWorker, args: %{"self_hosted" => true}} in crontab
      assert {"30 3 * * *", DeleteExpiredGradleCacheArtifactsWorker, args: %{"self_hosted" => true}} in crontab
      assert {"45 3 * * *", DeleteExpiredCasCacheArtifactsWorker, args: %{"self_hosted" => true}} in crontab

      refute Enum.any?(crontab, &(cron_worker(&1) == ScheduleExpiredArtifactsWorker))
      refute Enum.any?(crontab, &(cron_worker(&1) == DeleteExpiredLegacyBuildArtifactsWorker))
    end

    test ":web + prod-like env, Tuist-hosted and self-hosted share the cache retention schedules" do
      hosted_cache_crons =
        :web
        |> RuntimeConfig.crontab(:prod, true, %{})
        |> Enum.filter(&(cron_worker(&1) in @cache_retention_workers))
        |> Enum.map(fn {schedule, worker} -> {schedule, worker} end)
        |> Enum.sort()

      self_hosted_cache_crons =
        :web
        |> RuntimeConfig.crontab(:prod, false, %{cache_artifacts: 21})
        |> Enum.filter(&(cron_worker(&1) in @cache_retention_workers))
        |> Enum.map(fn {schedule, worker, _opts} -> {schedule, worker} end)
        |> Enum.sort()

      assert hosted_cache_crons == self_hosted_cache_crons
    end

    test ":web + prod-like env, Tuist-hosted: hosted-only entries plus shared crons" do
      for env <- [:prod, :stag, :can], artifact_retention_days <- [%{}, %{cache_artifacts: 21}] do
        workers =
          :web
          |> RuntimeConfig.crontab(env, true, artifact_retention_days)
          |> Enum.map(fn {_cron, worker} -> worker end)

        assert AutomationScheduler in workers
        assert AlertWorker in workers
        assert ReportWorker in workers
        assert ExpireStaleTestRunsWorker in workers
        assert PruneArchivedLogsWorker in workers

        assert ExpireInteractiveSessionsWorker in workers
        assert DailySlackReportWorker in workers
        assert HourlySlackReportWorker in workers
        assert UpdateAllAccountsUsageWorker in workers
        assert ScheduleExpiredArtifactsWorker in workers
        assert DeleteExpiredCasCacheArtifactsWorker in workers
        assert DeleteExpiredLegacyBuildArtifactsWorker in workers
        assert DeleteExpiredXcodeCacheArtifactsWorker in workers
        assert DeleteExpiredXcodeModuleCacheArtifactsWorker in workers
        assert DeleteExpiredGradleCacheArtifactsWorker in workers
        assert SyncStripeMetersWorker in workers
        assert KuraReconciler in workers
        assert StaleQueuedJobsWorker in workers
      end
    end
  end

  defp cron_worker({_schedule, worker}), do: worker
  defp cron_worker({_schedule, worker, _opts}), do: worker
end
