defmodule TuistCommon.HTTP.TransportPromExPluginTest do
  use ExUnit.Case, async: true

  alias TuistCommon.HTTP.TransportPromExPlugin

  describe "event_metrics/1" do
    test "tracks Bandit timeout counters from native events" do
      [timeout_event | _] = TransportPromExPlugin.event_metrics([])
      [timeout_metric] = timeout_event.metrics

      assert timeout_metric.event_name == [:bandit, :request, :stop]
      assert timeout_metric.tags == [:method, :route]
      assert timeout_metric.keep.(%{error: "Body read timeout"}, %{})
      refute timeout_metric.keep.(%{}, %{})

      assert timeout_metric.tag_values.(%{
               conn: %{method: "POST", private: %{phoenix_route: "/foo"}, request_path: "/foo"}
             }) == %{method: "POST", route: "/foo", request_path: "/foo"}
    end

    test "tracks Bandit failures from native stop and exception events" do
      [_timeout_event, failure_event | _] = TransportPromExPlugin.event_metrics([])
      [stop_metric, exception_metric] = failure_event.metrics

      assert stop_metric.name == [:tuist, :http, :request, :failure, :stop, :count]
      assert stop_metric.event_name == [:bandit, :request, :stop]
      assert stop_metric.keep.(%{conn: %{status: 500}}, %{})

      assert stop_metric.tag_values.(%{
               conn: %{method: "GET", private: %{}, request_path: "/bar", status: 500},
               error: nil
             }) == %{
               method: "GET",
               route: "unknown",
               reason: "server_error",
               request_path: "/bar"
             }

      assert exception_metric.name == [:tuist, :http, :request, :failure, :exception, :count]
      assert exception_metric.event_name == [:bandit, :request, :exception]

      assert exception_metric.tag_values.(%{
               conn: %{method: "GET", private: %{}, request_path: "/bar"}
             }) == %{method: "GET", route: "unknown", reason: "exception", request_path: "/bar"}
    end

    test "tracks Thousand Island drop and error counters from native events" do
      [_timeout_event, _failure_event, drop_event, error_event] =
        TransportPromExPlugin.event_metrics([])

      [drop_metric] = drop_event.metrics
      [recv_metric, send_metric] = error_event.metrics

      assert drop_metric.event_name == [:thousand_island, :connection, :stop]
      assert drop_metric.keep.(%{error: :closed}, %{})
      assert drop_metric.tag_values.(%{error: :closed}) == %{reason: "closed"}

      assert recv_metric.name == [:tuist, :http, :connection, :error, :recv, :count]
      assert recv_metric.event_name == [:thousand_island, :connection, :recv_error]
      assert recv_metric.tag_values.(%{}) == %{event: "recv_error"}

      assert send_metric.name == [:tuist, :http, :connection, :error, :send, :count]
      assert send_metric.event_name == [:thousand_island, :connection, :send_error]
      assert send_metric.tag_values.(%{}) == %{event: "send_error"}
    end

    test "uses unique metric names for transport counters" do
      names =
        TransportPromExPlugin.event_metrics([])
        |> Enum.flat_map(& &1.metrics)
        |> Enum.map(& &1.name)

      assert Enum.uniq(names) == names
    end
  end
end
