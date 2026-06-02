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
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker
  alias Tuist.Slack.Workers.ReportWorker
  alias Tuist.Tests.Workers.ExpireStaleTestRunsWorker

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

  describe "crontab/3" do
    test "empty for every non-web mode in every prod-like env, regardless of hosted state" do
      for mode <- Environment.modes(),
          mode != :web,
          env <- [:prod, :stag, :can],
          tuist_hosted? <- [true, false] do
        assert RuntimeConfig.crontab(mode, env, tuist_hosted?) == [],
               "expected empty crontab for mode=#{inspect(mode)} env=#{inspect(env)} hosted=#{inspect(tuist_hosted?)}"
      end
    end

    test "empty for :web in non-prod-like envs" do
      for env <- [:dev, :test], tuist_hosted? <- [true, false] do
        assert RuntimeConfig.crontab(:web, env, tuist_hosted?) == []
      end
    end

    test ":web + prod-like env, self-hosted: shared crons only, no hosted-only entries" do
      for env <- [:prod, :stag, :can] do
        workers =
          :web
          |> RuntimeConfig.crontab(env, false)
          |> Enum.map(fn {_cron, worker} -> worker end)

        assert AutomationScheduler in workers
        assert AlertWorker in workers
        assert ReportWorker in workers
        assert ExpireStaleTestRunsWorker in workers
        assert PruneArchivedLogsWorker in workers

        refute DailySlackReportWorker in workers
        refute HourlySlackReportWorker in workers
        refute UpdateAllAccountsUsageWorker in workers
        refute SyncStripeMetersWorker in workers
        refute KuraReconciler in workers
      end
    end

    test ":web + prod-like env, Tuist-hosted: hosted-only entries plus shared crons" do
      for env <- [:prod, :stag, :can] do
        workers =
          :web
          |> RuntimeConfig.crontab(env, true)
          |> Enum.map(fn {_cron, worker} -> worker end)

        assert AutomationScheduler in workers
        assert AlertWorker in workers
        assert ReportWorker in workers
        assert ExpireStaleTestRunsWorker in workers
        assert PruneArchivedLogsWorker in workers

        assert DailySlackReportWorker in workers
        assert HourlySlackReportWorker in workers
        assert UpdateAllAccountsUsageWorker in workers
        assert SyncStripeMetersWorker in workers
        assert KuraReconciler in workers
      end
    end
  end
end
