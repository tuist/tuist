defmodule Tuist.HTTP.PromExPluginTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Finch.HTTP1.PoolMetrics
  alias Tuist.HTTP.PromExPlugin

  setup :set_mimic_from_context
  setup :verify_on_exit!

  describe "request event tag values" do
    test "extracts the response status from streamed Req responses" do
      tag_values = request_stop_tag_values()

      request = %{
        method: "GET",
        host: "productionresultssa11.blob.core.windows.net",
        path: "/actions-results/job-logs.txt",
        scheme: :https,
        query: "sv=2025-11-05",
        port: 443
      }

      req = Req.Request.new(method: :get, url: "https://productionresultssa11.blob.core.windows.net/job-logs.txt")
      resp = %Req.Response{status: 200}

      assert tag_values.(%{name: :pipeline, request: request, result: {:ok, {req, resp}}}) == %{
               name: :pipeline,
               response_status: 200,
               request_method: "GET",
               request_host: "productionresultssa11.blob.core.windows.net",
               request_path: "/actions-results/job-logs.txt",
               request_scheme: :https,
               request_query: "sv=2025-11-05",
               request_port: 443
             }
    end

    test "extracts the error from streamed Req failures" do
      tag_values = request_stop_tag_values()

      request = %{
        method: "GET",
        host: "productionresultssa0.blob.core.windows.net",
        path: "/actions-results/job-logs.txt",
        scheme: :https,
        query: "sv=2025-11-05",
        port: 443
      }

      req = Req.Request.new(method: :get, url: "https://productionresultssa0.blob.core.windows.net/job-logs.txt")
      resp = %Req.Response{status: 200}
      exception = %Mint.TransportError{reason: :timeout}

      assert tag_values.(%{name: :pipeline, request: request, result: {:error, exception, {req, resp}}}) == %{
               name: :pipeline,
               error: "Mint.TransportError",
               request_method: "GET",
               request_host: "productionresultssa0.blob.core.windows.net",
               request_path: "/actions-results/job-logs.txt",
               request_scheme: :https,
               request_query: "sv=2025-11-05",
               request_port: 443
             }
    end
  end

  describe "pool status polling" do
    test "reports configured and fallback pools without exposing fallback origins" do
      endpoint = "https://objects.example.com"
      stub(Tuist.Environment, :s3_endpoint, fn -> endpoint end)

      expect(Finch, :get_pool_status, 2, fn
        Tuist.Finch, ^endpoint ->
          {:ok,
           [
             %PoolMetrics{
               pool_index: 1,
               pool_size: 500,
               available_connections: 490,
               in_use_connections: 10
             }
           ]}

        Tuist.Finch, :default ->
          {:ok,
           %{
             {:https, "customer-one.example.com", 443} => [
               %PoolMetrics{
                 pool_index: 1,
                 pool_size: 64,
                 available_connections: 40,
                 in_use_connections: 24
               }
             ],
             {:https, "customer-two.example.com", 443} => [
               %PoolMetrics{
                 pool_index: 1,
                 pool_size: 64,
                 available_connections: 32,
                 in_use_connections: 32
               }
             ]
           }}
      end)

      handler_id = "http-pool-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        Tuist.Telemetry.event_name_http_queue_status(),
        fn _event, measurements, metadata, test_pid ->
          send(test_pid, {:pool_status, measurements, metadata})
        end,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      PromExPlugin.execute_http_queue_status_telemetry_event()

      assert_received {:pool_status, %{available_connections: 490, in_use_connections: 10},
                       %{url: ^endpoint, size: 500, index: 1}}

      assert_received {:pool_status, %{available_connections: 72, in_use_connections: 56},
                       %{url: "default", size: 128, index: 0}}
    end
  end

  defp request_stop_tag_values do
    []
    |> PromExPlugin.event_metrics()
    |> Enum.find(&(&1.group_name == :tuist_http_request_event_metrics))
    |> Map.fetch!(:metrics)
    |> Enum.find(&(&1.event_name == [:finch, :request, :stop]))
    |> Map.fetch!(:tag_values)
  end
end
