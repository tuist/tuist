defmodule PulseWeb.OTLPMetricsControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  setup do
    Memory.reset()
    :ok
  end

  test "JSON/protobuf gzip mirror response encoding and preserve the independent corpus" do
    for format <- [:json, :protobuf] do
      body = if format == :json, do: File.read!("test/fixtures/otlp/protoc-metrics.json"), else: Fixture.protobuf()
      response = request(format, :zlib.gzip(body), [{"content-encoding", "gzip"}])
      assert response.status == 200
      assert get_resp_header(response, "content-type") == [mime(format)]
      assert response.resp_body == if(format == :json, do: "{}", else: "")
      assert {:ok, samples} = Storage.query(:metrics, "default")
      assert length(samples) == 7
      assert Enum.all?(samples, &is_map(&1.otlp))
      Memory.reset()
    end
  end

  test "partial success is explicit and keyed invalid batches never publish subsets" do
    payload = Fixture.payload([Fixture.gauge([Fixture.point(), %{"asInt" => "1"}])])
    response = request(:json, Pulse.JSON.encode!(payload))
    assert json_response(response, 200)["partialSuccess"]["rejectedDataPoints"] == "1"
    assert {:ok, [_]} = Storage.query(:metrics, "default")
    Memory.reset()
    response = request(:protobuf, Fixture.protobuf(payload))
    assert response.status == 200
    assert <<10, _, 8, 1, 18, _::binary>> = response.resp_body
    Memory.reset()

    for format <- [:json, :protobuf] do
      body = if format == :json, do: Pulse.JSON.encode!(payload), else: Fixture.protobuf(payload)
      response = request(format, body, [{"idempotency-key", "invalid"}])
      assert response.status == 400
      assert {:ok, []} = Storage.query(:metrics, "default")
    end
  end

  test "integer-spelled negative zero is OTLP-only and zero exponents remain valid" do
    for token <- ["-0", "-0.0", "\"-0\"", "1e-0"] do
      body =
        ~s({"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"m","gauge":{"dataPoints":[{"timeUnixNano":"1","asDouble":#{token}}]}}]}]}]})

      assert request(:json, body).status == 200
      assert {:ok, [sample]} = Storage.query(:metrics, "default")

      if token == "1e-0",
        do: assert(sample.value == 1.0),
        else: assert(<<sample.value::float-64>> == <<0x8000000000000000::64>>)

      Memory.reset()
    end

    assert Pulse.JSON.decode!("-0") === 0
  end

  test "oversized numeric input and invalid media fail without appending" do
    payload =
      Fixture.payload([
        Fixture.gauge([Map.put(Fixture.point(), "asDouble", String.duplicate("1", 1025)), Fixture.point()])
      ])

    assert request(:json, Pulse.JSON.encode!(payload)).status == 413
    assert {:ok, []} = Storage.query(:metrics, "default")
    assert request(:protobuf, <<0>>).status == 400

    assert request(:protobuf, Fixture.protobuf(), [{"content-type", "application/octet-stream"}]).status ==
             415

    assert request(:protobuf, Fixture.protobuf(), [{"x-scope-orgid", ".."}]).status == 400
  end

  defp request(format, body, headers \\ []) do
    conn =
      Enum.reduce(headers, put_req_header(build_conn(), "content-type", mime(format)), fn {key, value}, conn ->
        put_req_header(conn, key, value)
      end)

    post(conn, "/v1/metrics", body)
  end

  defp mime(:json), do: "application/json"
  defp mime(:protobuf), do: "application/x-protobuf"
end
