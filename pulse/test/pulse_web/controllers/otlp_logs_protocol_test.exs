defmodule PulseWeb.OTLPLogsProtocolTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Logs
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.OTLPLogFixture, as: Fixture

  setup do
    Memory.reset()
    :ok
  end

  test "JSON and gzip protobuf accept the independently compiled corpus with exact response MIME" do
    for format <- [:json, :protobuf], gzip? <- [false, true] do
      payload = if format == :json, do: File.read!("test/fixtures/otlp/protoc-logs.json"), else: Fixture.protobuf()
      headers = [{"accept", mime(format)}]

      {payload, headers} =
        if gzip?, do: {:zlib.gzip(payload), [{"content-encoding", "gzip"} | headers]}, else: {payload, headers}

      response = request(format, payload, headers)
      assert response.status == 200
      assert get_resp_header(response, "content-type") == [mime(format)]
      assert response.resp_body == if(format == :json, do: "{}", else: "")
      assert {:ok, stored} = Storage.query(:logs, "default")
      assert length(stored) == 2
      Memory.reset()
    end
  end

  test "partial success and malformed protobuf use the request encoding" do
    payload = Fixture.payload([%{"timeUnixNano" => "1", "severityNumber" => 25}, List.last(Fixture.records())])
    json = request(:json, Pulse.JSON.encode!(payload))
    assert %{"partialSuccess" => %{"rejectedLogRecords" => "1"}} = json_response(json, 200)
    Memory.reset()
    proto = request(:protobuf, Fixture.protobuf(payload))
    assert proto.status == 200
    assert <<10, _length, 8, 1, 18, _message_length, _::binary>> = proto.resp_body
    assert get_resp_header(proto, "content-type") == ["application/x-protobuf"]
    assert {:ok, [_]} = Storage.query(:logs, "default")
    invalid = request(:protobuf, <<10, 128>>)
    assert invalid.status == 400
    assert <<8, 3, 18, _::binary>> = invalid.resp_body
  end

  test "an invalid keyed batch is never rewritten to its valid subset" do
    payload = Fixture.payload([%{"severityNumber" => 25}, List.last(Fixture.records())])
    response = request(:json, Pulse.JSON.encode!(payload), [{"idempotency-key", "same-batch"}])
    assert json_response(response, 400)["message"] == "invalid_otlp"
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "observed time is the query timestamp; unknown times use receive time only without a key" do
    now = System.system_time(:nanosecond)
    raw = %{"observedTimeUnixNano" => Integer.to_string(now), "body" => %{"stringValue" => "observed"}}
    assert request(:json, Pulse.JSON.encode!(Fixture.payload([raw]))).status == 200
    assert {:ok, [log]} = Storage.query(:logs, "default", start_ts: now, end_ts: now)
    assert log.timestamp_ns == now
    assert log.otlp["timeUnixNano"] == "0"
    Memory.reset()
    payload = Fixture.payload([%{"body" => %{"stringValue" => "unknown"}}])
    response = request(:json, Pulse.JSON.encode!(payload), [{"idempotency-key", "no-time"}])
    assert json_response(response, 400)["message"] == "missing_keyed_timestamp"
    assert {:ok, []} = Storage.query(:logs, "default")
    assert request(:json, Pulse.JSON.encode!(payload)).status == 200
    assert {:ok, [log]} = Storage.query(:logs, "default")
    assert log.timestamp_ns >= now
    assert log.otlp["timeUnixNano"] == "0"
    assert log.otlp["receivedTimeUnixNano"] == Integer.to_string(log.timestamp_ns)
  end

  test "zero/invalid trace context is unassociated but preserved, not a discarded log" do
    raw = %{
      "traceId" => String.duplicate("0", 32),
      "spanId" => String.duplicate("0", 16),
      "body" => %{"stringValue" => "no context"}
    }

    assert request(:json, Pulse.JSON.encode!(Fixture.payload([raw]))).status == 200
    assert {:ok, [log]} = Storage.query(:logs, "default")
    assert log.trace_id == nil
    assert log.span_id == nil
    assert log.otlp["traceId"] == raw["traceId"]
    assert log.body == "no context"
    assert {:ok, [log], 0} = Logs.decode(Fixture.payload([Map.put(raw, "traceId", "bad")]))
    assert log.trace_id == nil
    assert log.otlp["traceId"] == "bad"
  end

  test "OTLP JSON retains unquoted -0 and quoted numeric doubles, without changing general JSON" do
    for token <- ["-0", "\"-0\"", "\"-0.0\"", "-0.0"] do
      body = ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"doubleValue":#{token}}}]}]}]})
      assert request(:json, body).status == 200
      assert {:ok, [log]} = Storage.query(:logs, "default")
      assert <<log.body::float-64>> == <<0x8000000000000000::64>>
      Memory.reset()
    end

    body = ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"doubleValue":"1.5"}}]}]}]})
    assert request(:json, body).status == 200
    assert {:ok, [log]} = Storage.query(:logs, "default")
    assert log.body === 1.5
    assert Pulse.JSON.decode!("-0") === 0
    assert JSON.decode!(~s({"text":"escaped \\\" -0,", "doubleValue":-0}))["text"] == ~s(escaped \" -0,)
  end

  test "zero exponents remain valid and oversized numeric spellings reject the whole batch" do
    for token <- ["1e-0", "1E-0", "1.5e-0"] do
      body = ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"doubleValue":#{token}}}]}]}]})
      assert request(:json, body).status == 200
      assert {:ok, [log]} = Storage.query(:logs, "default")
      assert log.body == if(token == "1.5e-0", do: 1.5, else: 1.0)
      Memory.reset()
    end

    body =
      ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"doubleValue":"#{String.duplicate("1", 1025)}"}},{"body":{"stringValue":"valid sibling"}}]}]}]})

    response = request(:json, body)
    assert response.status == 413
    assert Pulse.JSON.decode!(response.resp_body)["message"] == "attributes_too_large"
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "ambiguous headers, path escape tenants and unsupported media types fail before storage" do
    for {headers, status} <- [
          {[{"x-scope-orgid", "."}], 400},
          {[{"content-type", "application/octet-stream"}], 415},
          {[{"content-encoding", "br"}], 415}
        ] do
      assert request(:protobuf, Fixture.protobuf(), headers).status == status
      assert {:ok, []} = Storage.query(:logs, "default")
    end

    conn = %{
      build_conn()
      | req_headers: [{"content-type", "application/x-protobuf"}, {"x-scope-orgid", "a"}, {"x-scope-orgid", "b"}]
    }

    assert post(conn, "/v1/logs", Fixture.protobuf()).status == 400
  end

  defp request(format, body, headers \\ []) do
    conn =
      Enum.reduce(headers, put_req_header(build_conn(), "content-type", mime(format)), fn {key, value}, conn ->
        put_req_header(conn, key, value)
      end)

    post(conn, "/v1/logs", body)
  end

  defp mime(:json), do: "application/json"
  defp mime(:protobuf), do: "application/x-protobuf"
end
