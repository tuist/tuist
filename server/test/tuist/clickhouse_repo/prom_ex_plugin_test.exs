defmodule Tuist.ClickHouseRepo.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseRepo.PromExPlugin
  alias TuistTestSupport.TelemetryCapture

  describe "tag_values/1" do
    test "labels a successful query" do
      assert PromExPlugin.tag_values(%{result: {:ok, %Ch.Result{rows: [[1]]}}}) ==
               %{repo: "clickhouse_read", result: "ok"}
    end

    test "labels an error ClickHouse returned with its code" do
      error = %Ch.Error{code: 159, message: "Code: 159. DB::Exception: Timeout exceeded"}

      assert PromExPlugin.tag_values(%{result: {:error, error}}) ==
               %{repo: "clickhouse_read", result: "clickhouse_159"}
    end

    test "labels a connection the client dropped by the transport reason" do
      assert PromExPlugin.tag_values(%{result: {:error, %Mint.TransportError{reason: :closed}}}) ==
               %{repo: "clickhouse_read", result: "transport_closed"}
    end

    test "labels a pool checkout that timed out" do
      error = DBConnection.ConnectionError.exception("connection not available", :queue_timeout)

      assert PromExPlugin.tag_values(%{result: {:error, error}}) ==
               %{repo: "clickhouse_read", result: "queue_timeout"}

      assert PromExPlugin.tag_values(%{result: {:error, %DBConnection.ConnectionError{message: "closed"}}}) ==
               %{repo: "clickhouse_read", result: "connection_error"}
    end

    test "labels any other failure as an error" do
      assert PromExPlugin.tag_values(%{result: {:error, %RuntimeError{message: "boom"}}}) ==
               %{repo: "clickhouse_read", result: "error"}
    end
  end

  describe "event_metrics/1" do
    test "exports a count and a duration histogram keyed by outcome" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      assert Enum.map(metrics, & &1.name) == [
               [:tuist, :clickhouse, :query, :count],
               [:tuist, :clickhouse, :query, :duration, :milliseconds]
             ]

      assert Enum.all?(metrics, &(&1.event_name == [:tuist, :click_house_repo, :query]))
      assert Enum.all?(metrics, &(&1.tags == [:repo, :result]))
    end
  end

  test "a query ClickHouse stops at max_execution_time is labelled as a ClickHouse timeout" do
    event_name = [:tuist, :click_house_repo, :query]
    event_ref = TelemetryCapture.attach_event_handlers([event_name])

    Task.async(fn -> :telemetry.execute(event_name, %{}, %{result: {:ok, %Ch.Result{}}}) end)
    |> Task.await()

    refute_received {^event_name, ^event_ref, _measurements, _metadata}

    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()
    ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)

    result = ClickHouseRepo.query("SELECT sleep(0.5)", %{}, settings: [max_execution_time: 0.1])

    ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)

    assert {:error, %Ch.Error{code: 159}} = result
    assert_received {^event_name, ^event_ref, %{total_time: total_time}, %{query: "SELECT sleep(0.5)"} = metadata}
    assert PromExPlugin.tag_values(metadata) == %{repo: "clickhouse_read", result: "clickhouse_159"}
    assert System.convert_time_unit(total_time, :native, :millisecond) >= 100
  end
end
