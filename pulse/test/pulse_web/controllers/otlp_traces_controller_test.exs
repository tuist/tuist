defmodule PulseWeb.OTLPTracesControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.Ingest
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.FailingStorage
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  defp request(body, type \\ "application/json", headers \\ []) do
    conn = build_conn() |> put_req_header("content-type", type)
    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    post(conn, "/v1/traces", body)
  end

  test "JSON and protobuf accept gzip, mirror encoding, and isolate tenants" do
    for {type, body} <- [
          {"application/json", Pulse.JSON.encode!(Fixture.payload())},
          {"application/x-protobuf", Fixture.protobuf()}
        ],
        gzip? <- [false, true] do
      Memory.reset()
      headers = [{"x-scope-orgid", "acme"}, {"accept", type}] ++ if(gzip?, do: [{"content-encoding", "gzip"}], else: [])
      conn = request(if(gzip?, do: :zlib.gzip(body), else: body), type, headers)
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == [type]
      assert {:ok, [%{service: "tuist-server", trace_id: id}]} = Storage.query(:traces, "acme")
      assert id == Fixture.trace_id()
      assert {:ok, []} = Storage.query(:traces, "default")
      assert {:ok, []} = Storage.query(:logs, "acme")
      assert {:ok, []} = Storage.query(:metrics, "acme")
    end
  end

  test "partial success counts invalid spans in the request encoding" do
    raw = Map.put(Fixture.span(), "spanId", String.duplicate("0", 16))
    payload = Fixture.payload([Fixture.span(), raw])
    conn = request(Pulse.JSON.encode!(payload))
    assert json_response(conn, 200)["partialSuccess"]["rejectedSpans"] == "1"
    assert get_resp_header(conn, "content-type") == ["application/json"]
    Memory.reset()
    conn = request(Fixture.protobuf(payload), "application/x-protobuf")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/x-protobuf"]
    assert <<10, _length, 8, 1, 18, _message_length, _message::binary>> = conn.resp_body
    assert {:ok, [_]} = Storage.query(:traces, "default")
  end

  test "real SDK exports with repeated attribute keys are stored, keeping the last value" do
    dir = Path.expand("../../fixtures/traces/duplicate_keys", __DIR__)

    for {file, spans, name, key, value} <- [
          {"erlang-sdk.protobuf", 5, "GET /fixture", "url.path", "/fixture"},
          {"rust-sdk.protobuf", 2, "GET /up", "http.response.status_code", "200"}
        ] do
      tenant = "dup-" <> Path.rootname(file)
      conn = request(File.read!(Path.join(dir, file)), "application/x-protobuf", [{"x-scope-orgid", tenant}])
      assert conn.status == 200
      assert conn.resp_body == ""
      assert {:ok, stored} = Storage.query(:traces, tenant)
      assert length(stored) == spans
      span = Enum.find(stored, &(&1.name == name))
      assert span.attributes[key] == value
      keys = Enum.map(span.otlp["attributes"], & &1["key"])
      assert keys == Enum.uniq(keys)
      assert span.dropped_attributes_count > 0
    end
  end

  test "partial success names the rejection reasons and counts them by bounded reason" do
    bad_id = Map.put(Fixture.span(), "spanId", String.duplicate("0", 16))
    backwards = Map.put(Fixture.span(), "endTimeUnixNano", "1")
    payload = Fixture.payload([Fixture.span(), bad_id, backwards, backwards])

    partial = json_response(request(Pulse.JSON.encode!(payload)), 200)["partialSuccess"]
    assert partial["rejectedSpans"] == "3"
    assert partial["errorMessage"] == "invalid records rejected: end_before_start=2, invalid_span_id=1"

    conn = request(Fixture.protobuf(payload), "application/x-protobuf")
    message = "invalid records rejected: end_before_start=2, invalid_span_id=1"
    assert conn.resp_body == Ingest.response_protobuf(3, message)

    metrics = Pulse.SelfMetrics.render()
    assert metrics =~ ~s(pulse_ingest_rejected_records_total{signal="traces",reason="end_before_start"} 4)
    assert metrics =~ ~s(pulse_ingest_rejected_records_total{signal="traces",reason="invalid_span_id"} 2)
    assert metrics =~ ~s(pulse_ingest_rejected_records_total{signal="traces",reason="invalid_kind"} 0)
    refute metrics =~ "tuist-server"
  end

  test "the node-local concurrent ingest bound answers a retryable 429 and frees slots of exited requests" do
    start_supervised!(Pulse.IngestAdmission)
    Pulse.Runtime.put_env(:pulse, Pulse.IngestAdmission, max_concurrent: 1)
    owner = self()

    holder =
      spawn(
        Pulse.Runtime.capture(fn ->
          :ok = Pulse.IngestAdmission.acquire()
          send(owner, :holding)
          receive do: (:stop -> :ok)
        end)
      )

    assert_receive :holding
    conn = request(Fixture.protobuf(), "application/x-protobuf")
    assert conn.status == 429
    assert get_resp_header(conn, "retry-after") == ["1"]
    assert {:ok, []} = Storage.query(:traces, "default")
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_ingest_admission_total{signal="traces",outcome="rejected"} 1\n)
    metrics = Pulse.Metrics.render()
    assert metrics =~ "\npulse_ingest_inflight_requests 1\n"
    assert metrics =~ "\npulse_ingest_max_concurrent_requests 1\n"

    # A holder that exits without releasing (for example, killed at its heap
    # cap) gives its slot back through the monitor.
    ref = Process.monitor(holder)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}
    _ = :sys.get_state(Pulse.Runtime.whereis(Pulse.IngestAdmission))
    assert Pulse.IngestAdmission.in_flight() == 0

    for _ <- 1..2, do: assert(request(Fixture.protobuf(), "application/x-protobuf").status == 200)
    assert Pulse.IngestAdmission.in_flight() == 0
  end

  test "empty batches and malformed requests" do
    assert json_response(request("{}"), 200) == %{}
    assert request(<<>>, "application/x-protobuf").status == 200
    assert request(<<0>>, "application/x-protobuf").status == 400
    assert request(~s({"resourceSpans":null})).status == 400
    assert request("bad", "application/octet-stream").status == 415
    assert request("{}", "application/json", [{"content-encoding", "snappy"}]).status == 415
    assert request("{}", "application/json", [{"x-scope-orgid", "../evil"}]).status == 400
    assert request("bad", "application/x-protobuf", [{"content-encoding", "gzip"}]).status == 400
  end

  test "native projection rejection is permanent, not an exporter retry loop" do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :trace_projection_invalid})

    for {body, type} <- [
          {Pulse.JSON.encode!(Fixture.payload()), "application/json"},
          {Fixture.protobuf(), "application/x-protobuf"}
        ] do
      conn = request(body, type, [{"idempotency-key", "stable"}])
      assert conn.status == 400
      assert get_resp_header(conn, "retry-after") == []
    end
  end

  test "unkeyed publication expiry retries fresh siblings but keyed expiry stays permanent" do
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    Pulse.Runtime.put_env(:pulse, FailingStorage, {:error, :retention_expired})
    body = Pulse.JSON.encode!(Fixture.payload())
    assert request(body).status == 503
    assert request(body, "application/json", [{"idempotency-key", "stable"}]).status == 400
  end

  test "ambiguous headers and dot path tenants reject without appending" do
    for name <- ["x-scope-orgid", "idempotency-key"] do
      conn = build_conn() |> put_req_header("content-type", "application/json")
      conn = %{conn | req_headers: [{name, "a"}, {name, "b"} | conn.req_headers]}
      assert post(conn, "/v1/traces", Pulse.JSON.encode!(Fixture.payload())).status == 400
    end

    for tenant <- [".", ".."], do: assert(request("{}", "application/json", [{"x-scope-orgid", tenant}]).status == 400)
    assert {:ok, []} = Storage.query(:traces, "default")
  end

  test "auth precedes semantic validation, with the same tenant policy as other receivers" do
    hash = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "secret"), case: :lower)
    Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{"acme" => hash})
    assert request(<<0>>, "application/x-protobuf", [{"x-scope-orgid", "acme"}]).status == 401

    assert request(Pulse.JSON.encode!(Fixture.payload()), "application/json", [
             {"x-scope-orgid", "acme"},
             {"authorization", "Bearer wrong"}
           ]).status == 401

    assert request(Pulse.JSON.encode!(Fixture.payload()), "application/json", [
             {"x-scope-orgid", "acme"},
             {"authorization", "Bearer secret"}
           ]).status == 200
  end

  test "wire and expanded protobuf body caps return 413 without storing spans" do
    assert request(:binary.copy(<<0>>, 4 * 1024 * 1024 + 1), "application/x-protobuf").status == 413
    Pulse.Runtime.put_env(:pulse, PulseWeb.CompressedBodyReader, max_decompressed_bytes: 100)
    conn = request(:zlib.gzip(Fixture.protobuf()), "application/x-protobuf", [{"content-encoding", "gzip"}])
    assert conn.status == 413
    assert get_resp_header(conn, "content-type") |> hd() |> String.starts_with?("application/x-protobuf")
    assert {:ok, []} = Storage.query(:traces, "default")
  end

  test "413 rejects the whole request and storage failure remains retryable" do
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 1)
    payload = Fixture.payload([Fixture.span(), Fixture.span()])
    assert request(Pulse.JSON.encode!(payload)).status == 413
    assert request(Fixture.protobuf(payload), "application/x-protobuf").status == 413
    assert {:ok, []} = Storage.query(:traces, "default")
    Pulse.Runtime.put_env(:pulse, Storage, adapter: FailingStorage)
    conn = request(Fixture.protobuf(), "application/x-protobuf")
    assert conn.status == 503
    assert get_resp_header(conn, "retry-after") == ["1"]
  end
end
