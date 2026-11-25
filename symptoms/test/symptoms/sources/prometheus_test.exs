defmodule Symptoms.Sources.PrometheusTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Symptoms.Sources.Prometheus

  test "instant and historical reads select Pulse's public database using its read-only identity" do
    stub(Req, :request, fn request ->
      assert request.url.host == "pulse.test"
      assert Req.Request.get_header(request, "x-pulse-db-name") == ["public"]
      assert request.options.auth == {:basic, "dashboard:test-token"}

      case request.url.path do
        "/v1/prometheus/api/v1/query" ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "status" => "success",
               "data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => [120, "7"]}]}
             }
           }}

        "/v1/prometheus/api/v1/query_range" ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "status" => "success",
               "data" => %{
                 "resultType" => "matrix",
                 "result" => [%{"metric" => %{}, "values" => [[60, "3"], [120, "7"]]}]
               }
             }
           }}
      end
    end)

    opts = [prometheus: [base_url: "http://pulse.test/v1/prometheus", user: "dashboard", token: "test-token"]]
    assert {:ok, [%{value: 7.0}]} = Prometheus.query("queue_depth", 120, opts)
    assert {:ok, [%{values: [{60, 3.0}, {120, 7.0}]}]} = Prometheus.query_range("queue_depth", 60, 120, 60, opts)
  end
end
