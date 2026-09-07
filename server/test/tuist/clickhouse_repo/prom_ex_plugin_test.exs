defmodule Tuist.ClickHouseRepo.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseRepo.PromExPlugin

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
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:tuist, :click_house_repo, :query],
      fn _event, measurements, metadata, _config ->
        if metadata.query =~ "sleep(0.5)", do: send(test_pid, {:query, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()
    ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)

    result = ClickHouseRepo.query("SELECT sleep(0.5)", %{}, settings: [max_execution_time: 0.1])

    ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)

    assert {:error, %Ch.Error{code: 159}} = result
    assert_receive {:query, %{total_time: total_time}, metadata}
    assert PromExPlugin.tag_values(metadata) == %{repo: "clickhouse_read", result: "clickhouse_159"}
    assert System.convert_time_unit(total_time, :native, :millisecond) >= 100
  end
end
