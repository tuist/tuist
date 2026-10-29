defmodule Tuist.PromEx.StripedPeepTest do
  use ExUnit.Case, async: false

  alias Tuist.PromEx.StripedPeep

  defp unique_id, do: String.replace(UUIDv7.generate(), "-", "_")

  describe "scrape/1" do
    test "keeps striped ETS tables intact after scraping metrics" do
      test_id = unique_id()
      name = :"test_peep_#{test_id}"
      event_name = [:test, String.to_atom(test_id), :counter]

      metrics = [Telemetry.Metrics.counter("test.#{test_id}.counter.count", tags: [:test])]
      opts = [name: name, metrics: metrics, storage: :striped]

      {:ok, _pid} = Peep.start_link(opts)

      :telemetry.execute(event_name, %{count: 1}, %{test: "value1"})
      :telemetry.execute(event_name, %{count: 1}, %{test: "value2"})

      metrics_before = Peep.get_all_metrics(name)
      assert map_size(metrics_before) > 0

      result = StripedPeep.scrape(name)
      assert is_binary(result)

      assert Peep.get_all_metrics(name) == metrics_before

      GenServer.stop(name)
    end

    test "handles different metric types" do
      test_id = unique_id()
      name = :"test_peep_mixed_#{test_id}"

      events = %{
        counter: ["test", test_id, "counter"],
        last_value: ["test", test_id, "last_value"],
        sum: ["test", test_id, "sum"]
      }

      metrics = [
        Telemetry.Metrics.counter(Enum.join(events.counter, ".")),
        Telemetry.Metrics.last_value(Enum.join(events.last_value, ".")),
        Telemetry.Metrics.sum(Enum.join(events.sum, "."))
      ]

      opts = [name: name, metrics: metrics, storage: :striped]
      {:ok, _pid} = Peep.start_link(opts)
      Process.sleep(50)

      :telemetry.execute(events.counter, %{}, %{type: "request"})
      :telemetry.execute(events.last_value, %{value: 42}, %{resource: "cpu"})
      :telemetry.execute(events.sum, %{bytes: 1024}, %{endpoint: "api"})
      Process.sleep(10)

      result = StripedPeep.scrape(name)
      assert is_binary(result)
      assert String.contains?(result, "# EOF")

      GenServer.stop(name)
    end

    test "handles non-striped storage" do
      test_id = unique_id()
      name = :"test_peep_default_#{test_id}"
      event_name = ["test", test_id, "counter"]

      metrics = [Telemetry.Metrics.counter(Enum.join(event_name, "."))]
      opts = [name: name, metrics: metrics, storage: :default]

      {:ok, _pid} = Peep.start_link(opts)
      Process.sleep(50)

      :telemetry.execute(event_name, %{}, %{test: "value"})
      Process.sleep(50)

      metrics_before = Peep.get_all_metrics(name) || %{}
      result = StripedPeep.scrape(name)
      assert is_binary(result)

      if map_size(metrics_before) > 0 do
        metrics_after = Peep.get_all_metrics(name) || %{}
        assert map_size(metrics_after) > 0
      end

      GenServer.stop(name)
    end

    test "handles non-existent Peep instance gracefully" do
      fake_name = :"non_existent_#{unique_id()}"

      result = StripedPeep.scrape(fake_name)
      assert is_binary(result)
      assert String.contains?(result, "# EOF")
    end

    test "accumulates counts across multiple scrape cycles" do
      test_id = unique_id()
      name = :"test_peep_cumulative_#{test_id}"
      event_name = [:test, String.to_atom(test_id), :cumulative]

      metrics = [Telemetry.Metrics.counter("test.#{test_id}.cumulative.count", tags: [:kind])]
      opts = [name: name, metrics: metrics, storage: :striped]

      {:ok, _pid} = Peep.start_link(opts)

      totals =
        for _cycle <- 1..3 do
          for _ <- 1..5, do: :telemetry.execute(event_name, %{count: 1}, %{kind: "test"})

          assert is_binary(StripedPeep.scrape(name))

          name
          |> Peep.get_all_metrics()
          |> Map.values()
          |> Enum.flat_map(&Map.values/1)
          |> Enum.sum()
        end

      assert totals == [5, 10, 15]

      GenServer.stop(name)
    end
  end

  describe "child_spec/2" do
    test "returns valid Peep child spec with striped storage" do
      test_id = unique_id()
      name = :"test_child_spec_#{test_id}"

      metrics = [
        Telemetry.Metrics.counter("test.child_spec.#{test_id}")
      ]

      result = StripedPeep.child_spec(name, metrics)

      assert is_map(result)
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :start)
      assert result.id == name

      assert {Peep, :start_link, [opts]} = result.start
      assert opts[:name] == name
      assert opts[:metrics] == metrics
      assert opts[:storage] == :striped
    end
  end
end
