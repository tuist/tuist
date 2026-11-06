defmodule Pulse.Loki.PushTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.Discovery
  alias Pulse.Loki.Push
  alias Pulse.Loki.PushProto
  alias Pulse.Record.Log

  test "returns {[], 0} for a payload without streams" do
    assert Push.decode(%{}) == {[], 0}
    assert Push.decode(%{"streams" => "not-a-list"}) == {[], 0}
  end

  test "decodes a stream with one value tuple" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api", "level" => "info"},
          "values" => [["1700000000000000000", "hello"]]
        }
      ]
    }

    assert {[
              %Log{
                timestamp_ns: 1_700_000_000_000_000_000,
                observed_timestamp_ns: nil,
                severity_text: "info",
                service: "api",
                body: "hello",
                trace_id: nil,
                span_id: nil,
                attributes: %{},
                resource: %{"service_name" => "api", "level" => "info"}
              }
            ], 0} = Push.decode(payload)
  end

  test "falls back to `service` label when `service_name` is absent" do
    # Older Alloy configs and hand-rolled clients emit `service` rather
    # than the Grafana 3.0 `service_name` convention. Storing the value
    # on `Log.service` under either name keeps queries uniform.
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service" => "legacy"},
          "values" => [["1", "line"]]
        }
      ]
    }

    assert {[%Log{service: "legacy"}], 0} = Push.decode(payload)
  end

  test "prefers service_name over the fallback service label" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "new", "service" => "old"},
          "values" => [["1", "line"]]
        }
      ]
    }

    assert {[%Log{service: "new"}], 0} = Push.decode(payload)
  end

  test "falls back to detected_level when level is absent" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"detected_level" => "warn"},
          "values" => [["1", "line"]]
        }
      ]
    }

    assert {[%Log{severity_text: "warn"}], 0} = Push.decode(payload)
  end

  test "keeps the raw label map in resource, including lifted service and level" do
    # Lifting into dedicated Log fields is a query convenience — the
    # source labels stay in `resource` so a caller looking at the stored
    # record can see exactly what the sender emitted.
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api", "level" => "info", "k8s.namespace" => "prod"},
          "values" => [["1", "line"]]
        }
      ]
    }

    assert {[%Log{resource: resource}], 0} = Push.decode(payload)
    assert resource["service_name"] == "api"
    assert resource["level"] == "info"
    assert resource["k8s.namespace"] == "prod"
  end

  test "lifts trace_id and span_id out of structured metadata" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api"},
          "values" => [
            [
              "1",
              "line",
              %{"trace_id" => "abc", "span_id" => "def", "user_id" => "u1"}
            ]
          ]
        }
      ]
    }

    assert {[
              %Log{
                trace_id: "abc",
                span_id: "def",
                attributes: %{"user_id" => "u1"}
              }
            ], 0} = Push.decode(payload)
  end

  test "counts an entry with a missing timestamp as rejected" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api"},
          "values" => [
            ["1", "ok"],
            [nil, "no ts"]
          ]
        }
      ]
    }

    assert {[%Log{body: "ok"}], 1} = Push.decode(payload)
  end

  test "accepts numeric timestamps too" do
    # The Loki wire spec calls for strings; a handful of clients emit
    # integers. Accepting both avoids a class of "why is nothing landing"
    # bugs while keeping the string form as the canonical.
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api"},
          "values" => [[1_700_000_000_000_000_000, "hi"]]
        }
      ]
    }

    assert {[%Log{timestamp_ns: 1_700_000_000_000_000_000}], 0} = Push.decode(payload)
  end

  test "counts a values entry with a non-string line as rejected" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "api"},
          "values" => [
            ["1", "ok"],
            ["2", 42],
            ["3", %{"json" => "line"}]
          ]
        }
      ]
    }

    assert {[%Log{body: "ok"}], 2} = Push.decode(payload)
  end

  test "counts a whole stream as rejected when `stream` is not a map" do
    # A malformed stream still names its values; counting them as
    # rejects gives the sender an honest tally rather than pretending
    # nothing arrived.
    payload = %{
      "streams" => [
        %{
          "stream" => "not-a-map",
          "values" => [["1", "a"], ["2", "b"]]
        }
      ]
    }

    assert {[], 2} = Push.decode(payload)
  end

  test "flattens multiple streams" do
    payload = %{
      "streams" => [
        %{
          "stream" => %{"service_name" => "a"},
          "values" => [["1", "a1"], ["2", "a2"]]
        },
        %{
          "stream" => %{"service_name" => "b"},
          "values" => [["3", "b1"]]
        }
      ]
    }

    assert {records, 0} = Push.decode(payload)
    assert length(records) == 3
    assert Enum.map(records, & &1.service) == ["a", "a", "b"]
    assert Enum.map(records, & &1.body) == ["a1", "a2", "b1"]
    assert Enum.map(records, & &1.timestamp_ns) == [1, 2, 3]
  end

  test "empty values list produces no records and no rejects" do
    payload = %{
      "streams" => [
        %{"stream" => %{"service_name" => "api"}, "values" => []}
      ]
    }

    assert {[], 0} = Push.decode(payload)
  end

  describe "decode_protobuf/2" do
    @max 16 * 1024 * 1024
    # A literal backslash, so escape sequences in label fixtures are built
    # explicitly rather than written inside string literals.
    @bs <<92>>

    defp compress(%PushProto.PushRequest{} = request) do
      {iodata, _size} = PushProto.PushRequest.encode!(request)
      compress(IO.iodata_to_binary(iodata))
    end

    # snappyer returns "" for empty input, which is not a valid Snappy
    # block; Go's `snappy.Encode` (what Alloy uses) emits a lone 0x00
    # length header.
    defp compress(""), do: <<0>>

    defp compress(bytes) when is_binary(bytes) do
      {:ok, compressed} = :snappyer.compress(bytes)
      compressed
    end

    defp entry(opts \\ []) do
      %PushProto.Entry{
        timestamp: Keyword.get(opts, :timestamp, %PushProto.Timestamp{seconds: 1, nanos: 0}),
        line: Keyword.get(opts, :line, "line"),
        structured_metadata:
          for({k, v} <- Keyword.get(opts, :metadata, []), do: %PushProto.LabelPair{name: k, value: v})
      }
    end

    defp request(streams) do
      %PushProto.PushRequest{
        streams: for({labels, entries} <- streams, do: %PushProto.Stream{labels: labels, entries: entries})
      }
    end

    defp decode(request), do: Push.decode_protobuf(compress(request), @max)

    @tag :label_parsing_batch
    test "complete Loki label-set table preserves source labels and normalized discovery values" do
      fixture = File.read!("test/fixtures/logs/loki-upstream/label-parsing.json") |> Pulse.JSON.decode!()
      table = Enum.find(fixture["tables"], &(&1["name"] == "TestParseLabels"))
      assert length(table["rows"]) == 4

      for row <- table["rows"] do
        labels = Base.decode64!(row["query_bytes_base64"])
        expected = Map.new(row["expected_labels"], &{&1["name"], &1["value"]})
        assert {:ok, [record], 0} = decode(request([{labels, [entry()]}]))
        assert Discovery.labels(record) == expected

        if row["source_index"] == 3 do
          # Loki drops this label during ParseLabels. Pulse deliberately keeps
          # the original source map, normalizing only the discovery projection.
          assert record.resource == Map.put(expected, "bar", "")
          refute Map.has_key?(expected, "bar")
        else
          assert record.resource == expected
        end
      end

      [control] = fixture["controls"]
      assert control["reject"]
      assert control["repeat_count"] == 16_777_216
      labels = :binary.copy(Base.decode64!(control["repeat_bytes_base64"]), control["repeat_count"])
      # The public decoder rejects the same bytes at its decompressed request
      # cap, not as an exact replay of Go's standalone label-parser error.
      assert {:error, :payload_too_large} = decode(request([{labels, [entry()]}]))
    end

    test "decodes a well-formed stream with structured metadata" do
      req =
        request([
          {~s({service_name="api", level="info"}),
           [
             entry(
               timestamp: %PushProto.Timestamp{seconds: 1_700_000_000, nanos: 42},
               line: "hello",
               metadata: [{"trace_id", "abc"}, {"span_id", "def"}, {"user_id", "u1"}]
             )
           ]}
        ])

      assert {:ok,
              [
                %Log{
                  timestamp_ns: 1_700_000_000_000_000_042,
                  observed_timestamp_ns: nil,
                  severity_number: nil,
                  severity_text: "info",
                  service: "api",
                  body: "hello",
                  trace_id: "abc",
                  span_id: "def",
                  attributes: %{"user_id" => "u1"},
                  resource: %{"service_name" => "api", "level" => "info"}
                }
              ], 0} = decode(req)
    end

    test "falls back to the `service` and `detected_level` labels" do
      req = request([{~s({service="legacy", detected_level="warn"}), [entry()]}])
      assert {:ok, [%Log{service: "legacy", severity_text: "warn"}], 0} = decode(req)
    end

    test "treats blank trace_id and span_id as absent" do
      req = request([{"{}", [entry(metadata: [{"trace_id", ""}, {"span_id", ""}])]}])
      assert {:ok, [%Log{trace_id: nil, span_id: nil, attributes: attributes}], 0} = decode(req)
      assert attributes == %{}
    end

    test "counts a missing or out-of-range timestamp as one reject each" do
      req =
        request([
          {~s({service_name="api"}),
           [
             entry(line: "ok"),
             entry(timestamp: nil, line: "no ts"),
             entry(timestamp: %PushProto.Timestamp{seconds: -1, nanos: 0}, line: "negative")
           ]}
        ])

      assert {:ok, [%Log{body: "ok"}], 2} = decode(req)
    end

    test "rejects a record whose line is not valid UTF-8 without failing the batch" do
      # One bad byte used to fail the whole request with 400, and Alloy does
      # not retry 4xx, so the rest of the batch was silently dropped.
      {iodata, _} =
        PushProto.PushRequest.encode!(request([{"{}", [entry(line: "good"), entry(line: "BAD!")]}]))

      bytes = iodata |> IO.iodata_to_binary() |> :binary.replace("BAD!", <<0xFF, 0xFE, 0xFD, 0xFC>>)

      assert {:ok, [%Log{body: "good"}], 1} = Push.decode_protobuf(compress(bytes), @max)
    end

    test "counts every entry as rejected when the labels string is malformed" do
      req = request([{"not a valid label string", [entry(), entry()]}, {"{}", [entry(line: "kept")]}])
      assert {:ok, [%Log{body: "kept"}], 2} = decode(req)
    end

    test "rejects a stream whose label value decodes to invalid UTF-8" do
      labels = "{k=\"" <> @bs <> "xff\"}"
      assert {:ok, [], 1} = decode(request([{labels, [entry()]}]))
    end

    test "decodes Go escapes in label values" do
      labels =
        "{a=\"q" <> @bs <> "\"x" <> @bs <> "\"\", b=\"caf" <> @bs <> "u00e9\", c=\"" <> @bs <> "101" <> @bs <> "x42\"}"

      assert {:ok, [%Log{resource: resource}], 0} = decode(request([{labels, [entry()]}]))
      assert resource == %{"a" => ~s(q"x"), "b" => "caf" <> <<0xC3, 0xA9>>, "c" => "AB"}
    end

    test "resolves duplicate labels and metadata last-wins" do
      req =
        request([
          {~s({a="1", b="2", a="3",}),
           [entry(metadata: [{"user", "first"}, {"trace_id", "t1"}, {"user", "second"}, {"trace_id", "t2"}])]}
        ])

      assert {:ok, [%Log{resource: resource, attributes: attributes, trace_id: "t2"}], 0} = decode(req)
      assert resource == %{"a" => "3", "b" => "2"}
      assert attributes == %{"user" => "second"}
    end

    test "flattens multiple streams in order" do
      req =
        request([
          {~s({service_name="a"}), [entry(line: "a1"), entry(line: "a2")]},
          {~s({service_name="b"}), [entry(line: "b1")]}
        ])

      assert {:ok, records, 0} = decode(req)
      assert Enum.map(records, &{&1.service, &1.body}) == [{"a", "a1"}, {"a", "a2"}, {"b", "b1"}]
    end

    test "an empty request or stream produces no records and no rejects" do
      assert {:ok, [], 0} = decode(request([]))
      assert {:ok, [], 0} = decode(request([{"{}", []}]))
    end

    test "returns record strings as sub-binaries of the decompressed body" do
      line = String.duplicate("x", 200)
      assert {:ok, [%Log{body: body}], 0} = decode(request([{"{}", [entry(line: line)]}]))
      assert body == line
      assert :binary.referenced_byte_size(body) > byte_size(body)
    end

    test "reports invalid Snappy, invalid protobuf, and oversized payloads" do
      assert {:error, :invalid_snappy} = Push.decode_protobuf("not snappy data at all", @max)
      assert {:error, :invalid_snappy} = Push.decode_protobuf("", @max)
      assert {:error, :invalid_protobuf} = Push.decode_protobuf(compress("random bytes"), @max)

      body = compress(request([{"{}", [entry(line: String.duplicate("x", 2048))]}]))
      assert {:error, :payload_too_large} = Push.decode_protobuf(body, 1024)
    end

    test "never raises on mutated or random input" do
      {iodata, _} =
        PushProto.PushRequest.encode!(
          request([{~s({service_name="api"}), [entry(metadata: [{"trace_id", "abc"}]), entry(line: "two")]}])
        )

      valid = IO.iodata_to_binary(iodata)

      for _ <- 1..3_000 do
        mutated =
          case :rand.uniform(3) do
            1 -> binary_part(valid, 0, :rand.uniform(byte_size(valid)))
            2 -> flip_random_byte(valid)
            3 -> :crypto.strong_rand_bytes(:rand.uniform(64))
          end

        for input <- [compress(mutated), mutated] do
          assert well_formed?(Push.decode_protobuf(input, @max))
        end
      end
    end

    defp well_formed?({:ok, records, rejected}),
      do: is_list(records) and Enum.all?(records, &is_struct(&1, Log)) and is_integer(rejected)

    defp well_formed?({:error, reason}), do: reason in [:invalid_snappy, :invalid_protobuf, :payload_too_large]
    defp well_formed?(_), do: false

    defp flip_random_byte(binary) do
      at = :rand.uniform(byte_size(binary)) - 1
      <<head::binary-size(^at), byte, rest::binary>> = binary
      <<head::binary, Bitwise.bxor(byte, :rand.uniform(255)), rest::binary>>
    end
  end
end
