defmodule Tuist.ClickHouse.Workers.ParityWorkerTest do
  use ExUnit.Case, async: true

  use Mimic

  alias Tuist.ClickHouse.Parity
  alias Tuist.ClickHouse.Workers.ParityWorker

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

        {:ok, %{compared: 3, matching: [], differing: [], skipped: [], derived: %{}}}
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

    test "reports a difference without failing the job" do
      # Returning an error would make Oban retry, and the retry compares a
      # window that has since moved, turning one real difference into several.
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)

      expect(Parity, :compare, fn _opts ->
        {:ok, %{compared: 2, matching: [], differing: [%{table: "build_runs"}], skipped: [], derived: %{}}}
      end)

      assert :ok = ParityWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
