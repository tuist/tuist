defmodule Tuist.HTTP.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.HTTP.PromExPlugin

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

  defp request_stop_tag_values do
    []
    |> PromExPlugin.event_metrics()
    |> Enum.find(&(&1.group_name == :tuist_http_request_event_metrics))
    |> Map.fetch!(:metrics)
    |> Enum.find(&(&1.event_name == [:finch, :request, :stop]))
    |> Map.fetch!(:tag_values)
  end
end
