defmodule Tuist.ReadinessTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Readiness

  describe "checks/1" do
    test "the xcresult processor checks Postgres, ClickHouse and its Oban queue" do
      assert Readiness.checks(:xcresult_processor) == [:postgres, :clickhouse, {:oban_queue, :process_xcresult}]
    end

    test "every other mode has no checks" do
      for mode <- Environment.modes(), mode != :xcresult_processor do
        assert Readiness.checks(mode) == []
      end
    end
  end

  describe "check/2" do
    test "passes when every dependency is reachable" do
      stub(Oban, :check_queue, fn [queue: :process_xcresult] -> %{paused: false} end)

      assert {:ok, results} = Readiness.check([:postgres, :clickhouse, {:oban_queue, :process_xcresult}])
      assert results == %{"postgres" => :ok, "clickhouse" => :ok, "oban_queue_process_xcresult" => :ok}
    end

    test "fails when Postgres is unreachable" do
      stub(Tuist.Repo, :query, fn "SELECT 1", [], _opts ->
        {:error, %DBConnection.ConnectionError{message: "connection refused"}}
      end)

      assert {:error, %{"postgres" => {:error, %DBConnection.ConnectionError{}}, "clickhouse" => :ok}} =
               Readiness.check([:postgres, :clickhouse])
    end

    test "fails a check that does not answer within the timeout" do
      stub(Tuist.IngestRepo, :query, fn "SELECT 1", [], _opts ->
        Process.sleep(1_000)
        {:ok, %{rows: [[1]]}}
      end)

      assert {:error, %{"clickhouse" => {:error, :timeout}, "postgres" => :ok}} =
               Readiness.check([:postgres, :clickhouse], timeout: 100)
    end

    test "fails when the Oban queue is paused" do
      stub(Oban, :check_queue, fn [queue: :process_xcresult] -> %{paused: true} end)

      assert {:error, %{"oban_queue_process_xcresult" => {:error, :paused}}} =
               Readiness.check([{:oban_queue, :process_xcresult}])
    end

    test "fails when the Oban queue is not running" do
      stub(Oban, :check_queue, fn [queue: :process_xcresult] -> exit({:noproc, {GenServer, :call, []}}) end)

      assert {:error, %{"oban_queue_process_xcresult" => {:error, {:exit, {:noproc, _}}}}} =
               Readiness.check([{:oban_queue, :process_xcresult}])
    end

    test "fails when Oban itself is not running" do
      stub(Oban, :check_queue, fn [queue: :process_xcresult] ->
        raise ArgumentError, "unknown registry: Oban.Registry"
      end)

      assert {:error, %{"oban_queue_process_xcresult" => {:error, %ArgumentError{}}}} =
               Readiness.check([{:oban_queue, :process_xcresult}])
    end
  end
end
