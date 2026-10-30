defmodule Tuist.ClickHouseRepo.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseRepo.PromExPlugin
  alias Tuist.PromEx.StripedPeep
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

      assert Enum.all?(metrics, &(&1.event_name == [:tuist, :clickhouse, :read, :query]))
      assert Enum.all?(metrics, &(&1.tags == [:repo, :result]))
    end
  end

  test "exports read events without duplicate metric families", context do
    owner = self()

    metrics =
      []
      |> PromExPlugin.event_metrics()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.map(&%{&1 | keep: fn _ -> self() == owner end})

    start_supervised!(StripedPeep.child_spec(context.test, metrics))
    measurements = %{total_time: System.convert_time_unit(2, :millisecond, :native)}

    :telemetry.execute([:tuist, :click_house_repo, :query], measurements, %{
      repo: ClickHouseRepo,
      result: {:ok, %{}},
      query: "private query text",
      params: ["private parameter"]
    })

    output = StripedPeep.scrape(context.test)

    tags = ~s(repo="clickhouse_read",result="ok")
    assert output =~ ~s(tuist_clickhouse_query_count{#{tags}} 1)
    assert output =~ ~s(tuist_clickhouse_query_duration_milliseconds_sum{#{tags}} 2)

    refute output =~ "private"
    assert length(Regex.scan(~r/^# TYPE tuist_clickhouse_query_count counter$/m, output)) == 1
    assert length(Regex.scan(~r/^# TYPE tuist_clickhouse_query_duration_milliseconds histogram$/m, output)) == 1
  end

  test "ignores ops events even when they have a result" do
    event_name = [:tuist, :clickhouse, :read, :query]
    event_ref = TelemetryCapture.attach_event_handlers([event_name])
    measurements = %{total_time: System.convert_time_unit(2, :millisecond, :native)}

    assert :ok =
             PromExPlugin.handle_query([:tuist, :ops_click_house_repo, :query], measurements, %{result: {:ok, %{}}}, nil)

    refute_received {^event_name, ^event_ref, _, _}

    PromExPlugin.handle_query([:tuist, :click_house_repo, :query], measurements, %{result: {:ok, %{}}}, nil)
    assert_received {^event_name, ^event_ref, ^measurements, %{repo: "clickhouse_read", result: "ok"}}
  end

  test "a query ClickHouse stops at max_execution_time is labelled as a ClickHouse timeout", context do
    opts = Keyword.merge(ClickHouseRepo.config(), name: context.test, pool: DBConnection.ConnectionPool, pool_size: 1)
    start_supervised!({ClickHouseRepo, opts})
    event_name = [:tuist, :click_house_repo, :query]
    event_ref = TelemetryCapture.attach_event_handlers([event_name])

    fn -> :telemetry.execute(event_name, %{}, %{result: {:ok, %Ch.Result{}}}) end
    |> Task.async()
    |> Task.await()

    refute_received {^event_name, ^event_ref, _measurements, _metadata}

    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()
    ClickHouseRepo.put_dynamic_repo(context.test)

    result =
      try do
        ClickHouseRepo.query("SELECT sleep(0.5)", %{}, settings: [max_execution_time: 0.1])
      after
        ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)
      end

    assert {:error, %Ch.Error{code: 159}} = result
    assert_received {^event_name, ^event_ref, %{total_time: total_time}, %{query: "SELECT sleep(0.5)"} = metadata}
    assert PromExPlugin.tag_values(metadata) == %{repo: "clickhouse_read", result: "clickhouse_159"}
    assert System.convert_time_unit(total_time, :native, :millisecond) >= 100
  end
end
