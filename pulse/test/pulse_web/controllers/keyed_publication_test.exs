defmodule PulseWeb.KeyedPublicationTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.OTLPLogFixture, as: Logs
  alias Pulse.Test.OTLPMetricFixture, as: Metrics
  alias Pulse.Test.OTLPTraceFixture, as: Traces

  setup do
    Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Runtime.put_env(:pulse, FailingStorage, {:error, :keyed_content_mismatch})
    :ok
  end

  test "all OTLP receivers expose a permanent conflict in JSON and protobuf without retry-after" do
    logs = %{
      "resourceLogs" => [
        %{"scopeLogs" => [%{"logRecords" => [%{"timeUnixNano" => "1", "body" => %{"stringValue" => "test"}}]}]}
      ]
    }

    metrics = Metrics.payload([Metrics.gauge([Metrics.point()])])
    traces = Traces.payload([Traces.span(10)])

    for {path, payload, protobuf} <- [
          {"/v1/logs", logs, Logs.protobuf(logs)},
          {"/v1/metrics", metrics, Metrics.protobuf(metrics)},
          {"/v1/traces", traces, Traces.protobuf(traces)}
        ],
        {type, body} <- [{"application/json", Pulse.JSON.encode!(payload)}, {"application/x-protobuf", protobuf}] do
      response =
        build_conn()
        |> put_req_header("content-type", type)
        |> put_req_header("idempotency-key", "key")
        |> post(path, body)

      assert response.status == 409
      assert get_resp_header(response, "retry-after") == []

      if type == "application/json" do
        assert json_response(response, 409) == %{"code" => 6, "message" => "keyed_content_mismatch"}
      else
        assert response.resp_body == <<8, 6, 18, 22, "keyed_content_mismatch">>
      end
    end
  end

  test "Loki and remote-write conflict responses are permanent instead of endlessly retryable" do
    response =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "key")
      |> post("/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service_name" => "api"}, "values" => [["1", "hello"]]}]
      })

    assert json_response(response, 409) == %{"error" => "keyed_content_mismatch"}
    assert get_resp_header(response, "retry-after") == []

    label = field(1, "__name__") <> field(2, "work")
    sample = <<9, 1.0::little-float-64, 16, 1>>
    wire = field(1, field(1, label) <> field(2, sample))
    {:ok, compressed} = :snappyer.compress(wire)

    response =
      build_conn()
      |> put_req_header("content-type", "application/x-protobuf")
      |> put_req_header("content-encoding", "snappy")
      |> put_req_header("x-prometheus-remote-write-version", "0.1.0")
      |> put_req_header("idempotency-key", "key")
      |> post("/api/v1/write", compressed)

    assert json_response(response, 409) == %{"error" => "keyed_content_mismatch"}
    assert get_resp_header(response, "retry-after") == []
  end

  defp field(number, bytes), do: <<number * 8 + 2, byte_size(bytes), bytes::binary>>
end
