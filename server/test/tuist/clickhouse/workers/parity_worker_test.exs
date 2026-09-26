defmodule Tuist.ClickHouse.Workers.ParityWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouse.Parity
  alias Tuist.ClickHouse.Workers.ParityWorker

  defp no_drift, do: %{missing_on_destination: [], missing_on_source: [], differing_columns: []}

  describe "perform/1" do
    test "does not compare anything when writes are not being mirrored" do
      # Which is every environment that is not mid-migration. The worker sits
      # on the shared hourly crontab, so being inert is what keeps it from
      # comparing against a server that is not there.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> false end)
      reject(&Parity.compare/1)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end

    test "compares a bounded window rather than the whole dataset" do
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)

      expect(Parity, :compare, fn opts ->
        since = Keyword.fetch!(opts, :since)

        # Longer than the interval between runs, so a row arriving late still
        # lands inside some window rather than between two of them.
        assert DateTime.diff(DateTime.utc_now(), since, :hour) >= 1

        {:ok, %{compared: 3, matching: [], differing: [], skipped: [], derived: %{}, schema: no_drift()}}
      end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end

    test "stays quiet when there is no destination configured" do
      # An hourly job must not turn the normal state of every non-migrating
      # environment into noise, or into a retry.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)
      expect(Parity, :compare, fn _opts -> {:error, :no_target_configured} end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end

    test "counts schema drift as well as diverged rows" do
      # The two are reported separately because they are repaired differently:
      # rows by re-running the backfill, a drifted schema by migrating the
      # server that was missed.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)

      expect(Parity, :compare, fn _opts ->
        {:ok,
         %{
           compared: 2,
           matching: [],
           differing: [],
           skipped: [],
           derived: %{},
           schema: %{missing_on_destination: ["bazel_invocations"], missing_on_source: [], differing_columns: []}
         }}
      end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end

    test "measures how much of the dataset the window could not cover" do
      # A table leaves the hourly check by growing past what a window can
      # bound, and the tables that do are the largest ones. Without this the
      # only trace is `compared` falling, which is indistinguishable from
      # having fewer tables to compare.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)

      expect(Parity, :compare, fn _opts ->
        {:ok,
         %{
           compared: 54,
           matching: [],
           differing: [],
           skipped: ["build_files", "test_case_runs_by_commit", "test_case_runs_by_test_run"],
           derived: %{},
           schema: no_drift()
         }}
      end)

      handler = "parity-measurements-#{System.unique_integer([:positive])}"
      test = self()

      :telemetry.attach(
        handler,
        [:tuist, :clickhouse, :parity],
        fn _event, measurements, _metadata, _config -> send(test, {:parity, measurements}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})

      assert_received {:parity, %{compared: 54, skipped: 3}}
    end

    test "reports a difference without failing the job" do
      # Returning an error would make Oban retry, and the retry compares a
      # window that has since moved, turning one real difference into several.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)

      expect(Parity, :compare, fn _opts ->
        {:ok,
         %{compared: 2, matching: [], differing: [%{table: "build_runs"}], skipped: [], derived: %{}, schema: no_drift()}}
      end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
