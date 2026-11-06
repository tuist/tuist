defmodule PulseWeb.IngestLimitsTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.IngestLimits
  alias Pulse.Loki.PushProto
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  @receivers [:otlp, :loki_json, :loki_proto, :metrics]

  setup do
    Memory.reset()
    :ok
  end

  test "all receivers accept the exact record budget and reject the whole oversized batch" do
    configure(max_records: 2)

    for kind <- @receivers do
      assert ingest(kind, records: 2).status in [200, 204]
      assert {:ok, records} = Storage.query(signal(kind), "default")
      assert length(records) == 2
      Memory.reset()

      assert json_response(ingest(kind, records: 3), 413) == error_body(kind, "too_many_records")
      assert {:ok, []} = Storage.query(signal(kind), "default")
    end
  end

  test "all receivers enforce attribute count without truncation" do
    configure(max_attributes: 2)

    for kind <- @receivers do
      assert ingest(kind, attributes: [{"a", "1"}, {"b", "2"}]).status in [200, 204]
      Memory.reset()
      assert_attribute_error(kind, attributes: [{"a", "1"}, {"b", "2"}, {"c", "3"}])
    end
  end

  test "UTF-8 byte limits, not character counts, apply to keys and values" do
    configure(max_key_bytes: 4, max_value_bytes: 4)

    for kind <- @receivers do
      assert ingest(kind, attributes: [{"aaaa", "éé"}]).status in [200, 204]
      Memory.reset()
      assert_attribute_error(kind, attributes: [{"aaaaa", "v"}])
      assert_attribute_error(kind, attributes: [{"a", "ééa"}])
    end
  end

  test "aggregate key and value bytes are bounded independently of individual sizes" do
    configure(max_attribute_bytes: 8)

    for kind <- @receivers do
      assert ingest(kind, attributes: [{"a", "123"}, {"b", "456"}]).status in [200, 204]
      Memory.reset()
      assert_attribute_error(kind, attributes: [{"a", "123"}, {"b", "4567"}])
    end
  end

  test "duplicate raw OTLP and protobuf attributes cannot bypass the count limit" do
    configure(max_attributes: 2)

    for kind <- [:otlp, :loki_proto, :metrics] do
      assert_attribute_error(kind, attributes: List.duplicate({"a", "v"}, 3))
    end
  end

  test "stream labels and OTLP resource and scope attributes have the same limits" do
    configure(max_attributes: 2)
    attrs = [{"a", "v"}, {"b", "v"}, {"c", "v"}]
    assert_attribute_error(:otlp, resource: attrs)
    assert_attribute_error(:otlp, scope: attrs)
    assert_attribute_error(:loki_json, resource: attrs)
    assert_attribute_error(:loki_proto, resource: attrs)
  end

  test "Loki labels are checked after Go unescaping" do
    configure(max_value_bytes: 4)
    assert ingest(:loki_proto, raw_labels: ~s({a="\\x61\\x61\\x61\\x61"})).status == 204
    Memory.reset()
    assert_attribute_error(:loki_proto, raw_labels: ~s({a="\\x61\\x61\\x61\\x61\\x61"}))
  end

  test "malformed records count toward the budget across containers" do
    configure(max_records: 2)
    otlp = %{"resourceLogs" => [%{"scopeLogs" => [%{"logRecords" => [nil, nil, nil]}]}]}
    loki = %{"streams" => [%{"values" => [nil, nil]}, %{"values" => [nil]}]}
    assert json_response(post_json("/v1/logs", otlp), 413) == error_body(:otlp, "too_many_records")
    assert json_response(post_json("/loki/api/v1/push", loki), 413) == %{"error" => "too_many_records"}
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "empty containers cannot bypass work limits" do
    configure(max_records: 2)

    assert json_response(post_json("/v1/logs", %{"resourceLogs" => List.duplicate(%{}, 5)}), 413) ==
             error_body(:otlp, "too_many_records")

    assert json_response(post_json("/loki/api/v1/push", %{"streams" => [%{}, %{}, %{}]}), 413) ==
             %{"error" => "too_many_records"}

    for path <- ["/loki/api/v1/push", "/api/v1/write"] do
      assert json_response(post_proto(path, wire(1, "") |> :binary.copy(3)), 413) ==
               %{"error" => "too_many_records"}
    end
  end

  test "authentication takes precedence over record and attribute validation" do
    digest = :sha256 |> :crypto.hash("secret") |> Base.encode16(case: :lower)

    Pulse.Runtime.put_env(:pulse, Pulse.Auth,
      module: SharedSecret,
      tokens: %{"default" => "sha256$" <> digest}
    )

    configure(max_records: 2, max_attributes: 1)

    for kind <- @receivers do
      assert ingest(kind, records: 3, attributes: [{"a", "1"}, {"b", "2"}]).status == 401
      assert {:ok, []} = Storage.query(signal(kind), "default")
    end
  end

  test "gzip JSON requests obey the record budget after decompression" do
    configure(max_records: 2)

    requests = [
      {"/v1/logs", %{"resourceLogs" => [%{"scopeLogs" => [%{"logRecords" => List.duplicate(%{}, 3)}]}]}},
      {"/loki/api/v1/push", %{"streams" => [%{"stream" => %{}, "values" => List.duplicate(["1", "hello"], 3)}]}}
    ]

    for {path, payload} <- requests do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-encoding", "gzip")
        |> post(path, :zlib.gzip(Pulse.JSON.encode!(payload)))

      assert json_response(conn, 413) == error_body(path, "too_many_records")
      assert {:ok, []} = Storage.query(:logs, "default")
    end
  end

  test "JSON attribute nesting failures return 413 without storage writes" do
    configure(max_depth: 1)
    loki = %{"streams" => [%{"stream" => %{}, "values" => [["1", "hello", %{"a" => %{"b" => "v"}}]]}]}
    value = %{"arrayValue" => %{"values" => [%{"arrayValue" => %{"values" => [%{"stringValue" => "v"}]}}]}}
    otlp = %{"resourceLogs" => [%{"scopeLogs" => [%{"logRecords" => [%{"body" => value}]}]}]}
    assert json_response(post_json("/loki/api/v1/push", loki), 413) == %{"error" => "attributes_too_large"}
    assert json_response(post_json("/v1/logs", otlp), 413) == error_body(:otlp, "attributes_too_large")
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "malformed in-budget OTLP scope containers do not crash" do
    assert post_json("/v1/logs", %{"resourceLogs" => [%{"scopeLogs" => [nil, %{"logRecords" => "bad"}]}]}).status == 400
  end

  defp configure(options), do: Pulse.Runtime.put_env(:pulse, IngestLimits, options)

  defp assert_attribute_error(kind, opts) do
    assert json_response(ingest(kind, opts), 413) == error_body(kind, "attributes_too_large")
    assert {:ok, []} = Storage.query(signal(kind), "default")
  end

  defp error_body(kind, reason) when kind in [:otlp, "/v1/logs"], do: %{"code" => 8, "message" => reason}
  defp error_body(_, reason), do: %{"error" => reason}

  defp signal(:metrics), do: :metrics
  defp signal(_), do: :logs

  defp otlp_attrs(pairs) do
    Enum.map(pairs, fn {key, value} -> %{"key" => key, "value" => %{"stringValue" => value}} end)
  end

  defp ingest(kind, opts) do
    attributes = Keyword.get(opts, :attributes, [])
    resource = Keyword.get(opts, :resource, [])
    count = Keyword.get(opts, :records, 1)

    case kind do
      :otlp ->
        record = %{"timeUnixNano" => "1", "body" => %{"stringValue" => "hello"}, "attributes" => otlp_attrs(attributes)}

        payload = %{
          "resourceLogs" => [
            %{
              "resource" => %{"attributes" => otlp_attrs(resource)},
              "scopeLogs" => [
                %{
                  "scope" => %{"attributes" => otlp_attrs(Keyword.get(opts, :scope, []))},
                  "logRecords" => List.duplicate(record, count)
                }
              ]
            }
          ]
        }

        post_json("/v1/logs", payload)

      :loki_json ->
        post_json("/loki/api/v1/push", %{
          "streams" => [
            %{"stream" => Map.new(resource), "values" => List.duplicate(["1", "hello", Map.new(attributes)], count)}
          ]
        })

      :loki_proto ->
        labels =
          Keyword.get_lazy(opts, :raw_labels, fn -> label_string(resource) end)

        entry = %PushProto.Entry{
          timestamp: %PushProto.Timestamp{seconds: 1},
          line: "hello",
          structured_metadata: Enum.map(attributes, fn {k, v} -> %PushProto.LabelPair{name: k, value: v} end)
        }

        request = %PushProto.PushRequest{
          streams: [%PushProto.Stream{labels: labels, entries: List.duplicate(entry, count)}]
        }

        {iodata, _} = PushProto.PushRequest.encode!(request)
        post_proto("/loki/api/v1/push", IO.iodata_to_binary(iodata))

      :metrics ->
        labels = Enum.map_join(attributes, "", fn {k, v} -> wire(1, wire(1, k) <> wire(2, v)) end)
        # An empty label set is allowed by the budget but rejected by decoding.
        labels = if attributes == [], do: wire(1, wire(1, "__name__") <> wire(2, "up")), else: labels
        sample = wire(2, <<9, 1.0::little-float-64, 16, 1>>)
        post_proto("/api/v1/write", wire(1, labels <> :binary.copy(sample, count)))
    end
  end

  defp label_string(pairs) do
    "{" <> Enum.map_join(pairs, ",", fn {k, v} -> k <> "=" <> Pulse.JSON.encode!(v) end) <> "}"
  end

  defp post_json(path, payload) do
    build_conn() |> put_req_header("content-type", "application/json") |> post(path, Pulse.JSON.encode!(payload))
  end

  defp post_proto(path, payload) do
    {:ok, compressed} = :snappyer.compress(payload)

    build_conn()
    |> put_req_header("content-type", "application/x-protobuf")
    |> put_req_header("content-encoding", "snappy")
    |> post(path, compressed)
  end

  defp wire(field, bytes), do: varint(field * 8 + 2) <> varint(byte_size(bytes)) <> bytes
  defp varint(n) when n < 128, do: <<n>>
  defp varint(n), do: <<rem(n, 128) + 128>> <> varint(div(n, 128))
end
