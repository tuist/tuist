defmodule Pulse.Storage.LogMetadataCodecTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder

  test "historical log rollups retain sources, answer scans and merge into Pulse-only output" do
    dir = Path.expand("../../fixtures/metrics/legacy_1_38", __DIR__)
    legacy = File.read!(Path.join(dir, "log_rollup.parquet"))
    logs = File.read!(Path.join(dir, "logs.parquet"))
    minute = 60_000_000_000
    assert {:ok, ["source-a", "source-b"]} = NIF.log_rollup_sources(legacy)

    builder = NIF.log_rollup_new(0, minute, [minute])
    assert {:ok, 1} = NIF.log_rollup_add(builder, legacy, false, [minute])
    assert {:ok, 2} = NIF.log_rollup_add(builder, logs, true, [])
    assert {:ok, fresh, 1, [{^minute, 4}]} = NIF.log_rollup_finish(builder, ["source-c"])
    assert {:ok, ["source-c"]} = NIF.log_rollup_sources(fresh)
    assert :binary.match(fresh, "pulso.log.rollup.sources") == :nomatch

    for {blob, count} <- [{legacy, 2}, {fresh, 4}] do
      assert {:ok, scan} = NIF.log_metric_binned_new(:count, nil, 100)
      assert {:ok, 1} = NIF.log_metric_scan_rollup(scan, blob, [minute], nil, [])
      assert {:ok, [{labels, packed}]} = NIF.log_metric_scan_finish(scan)
      assert labels["service_name"] == "api"
      assert <<^minute::signed-64, 2, ^count::signed-64>> = packed
    end
  end

  test "legacy ten-column objects remain readable with explicitly absent OTLP metadata" do
    blob = File.read!("test/fixtures/logs/legacy_log.parquet")
    assert {:ok, [log]} = S3.decode_segment(:logs, blob, nil, nil, [])
    assert log.otlp == nil
    assert log.body == "legacy log"
    assert log.resource == %{"service.name" => "legacy-api"}
    assert log.timestamp_ns == 1_700_000_000_123_456_789
  end

  test "expanded-column budgets preserve legacy and rich log metadata" do
    legacy = File.read!("test/fixtures/logs/legacy_log.parquet")
    assert {:ok, [old], old_bytes} = S3.decode_log_segment_bounded(legacy, nil, nil, max_decoded_bytes: 1_048_576)
    assert old.otlp == nil
    assert old_bytes > 0
    record = %Log{timestamp_ns: 1, body: "rich", otlp: %{"body" => %{"stringValue" => "rich"}}}
    assert {:ok, blob, _, _} = S3.encode_segment(:logs, [record])
    assert {:ok, [^record], bytes} = S3.decode_log_segment_bounded(blob, nil, nil, max_decoded_bytes: 1_048_576)
    assert bytes > 0
    assert {:ok, [^record]} = S3.decode_segment(:logs, blob, nil, nil, max_decoded_bytes: 1_048_576)
  end

  test "duplicate sharing cannot bypass bounded log record quotas" do
    record = %Log{timestamp_ns: 1, body: "same", otlp: %{"body" => %{"stringValue" => "same"}}}
    assert {:ok, blob, _, _} = S3.encode_segment(:logs, [record, record])
    assert {:error, :query_sample_limit} = S3.decode_segment(:logs, blob, nil, nil, max_records: 1)

    assert {:error, :query_sample_limit} =
             S3.decode_log_segment_bounded(blob, nil, nil, max_records: 1, max_decoded_bytes: 1_048_576)

    assert {:ok, [^record, ^record], _} =
             S3.decode_log_segment_bounded(blob, nil, nil, max_records: 2, max_decoded_bytes: 1_048_576)
  end

  test "bounded log decoding rejects malformed present metadata" do
    for path <- ~w(invalid_otlp_type invalid_otlp_value) do
      assert {:error, {:decode_failed, _}} =
               S3.decode_segment(:logs, File.read!("test/fixtures/logs/#{path}.parquet"), nil, nil,
                 max_decoded_bytes: 1_048_576
               )
    end
  end

  test "a present malformed OTLP column cannot masquerade as a legacy absence" do
    for path <- ~w(invalid_otlp_type invalid_otlp_value) do
      assert {:error, {:decode_failed, _}} =
               S3.decode_segment(:logs, File.read!("test/fixtures/logs/#{path}.parquet"), nil, nil, [])
    end
  end

  test "record sharing preserves signed zeros in bodies, attributes, resources and typed envelopes" do
    records =
      for value <- [0.0, -0.0] do
        %Log{
          timestamp_ns: 1,
          body: %{"double" => value},
          attributes: %{"double" => value},
          resource: %{"double" => value},
          otlp: %{"body" => %{"doubleValue" => value}}
        }
      end

    assert {:ok, blob, _, _} = S3.encode_segment(:logs, records)
    assert {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])

    for {input, output} <- Enum.zip(records, decoded) do
      for field <- [:body, :attributes, :resource, :otlp] do
        assert :erlang.term_to_binary(Map.fetch!(input, field), [:deterministic]) ==
                 :erlang.term_to_binary(Map.fetch!(output, field), [:deterministic])
      end
    end

    refute :erts_debug.same(hd(decoded), List.last(decoded))
  end

  test "duplicates are preserved, while complete typed metadata resolves raw-query ties" do
    a = %Log{timestamp_ns: 1, body: "same", otlp: %{"body" => %{"stringValue" => "same"}, "scope" => %{"name" => "a"}}}
    b = %{a | otlp: put_in(a.otlp, ["scope", "name"], "b")}
    assert SortOrder.sort([a, b]) == SortOrder.sort([b, a])
    assert {:ok, blob, _, _} = S3.encode_segment(:logs, [a, a, b])
    assert {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
    assert decoded == [a, a, b]
    assert :erts_debug.same(hd(decoded), Enum.at(decoded, 1))
  end

  test "legacy/Loki fingerprints are stable, and typed metadata affects keyed identity" do
    log = %Log{timestamp_ns: 1, body: "hello"}

    fields = %{
      timestamp_ns: 1,
      observed_timestamp_ns: nil,
      severity_number: nil,
      severity_text: nil,
      service: nil,
      body: "hello",
      trace_id: nil,
      span_id: nil,
      attributes: %{},
      resource: %{}
    }

    expected =
      [fields]
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    assert {:ok, ^expected} = S3.caller_content_hash(:logs, [log])
    assert {:ok, a} = S3.caller_content_hash(:logs, [%{log | otlp: %{"body" => %{"stringValue" => "hello"}}}])
    assert {:ok, b} = S3.caller_content_hash(:logs, [%{log | otlp: %{"body" => %{"bytesValue" => "aGVsbG8="}}}])
    refute a == b
  end

  test "raw JSON results reject escaped output amplification before binary assembly" do
    record = %Log{timestamp_ns: 1, body: :binary.copy(<<0>>, 100_000)}
    assert {:ok, json, _, _, _} = NIF.encode_log_segment([record], :plain, :array)
    assert NIF.encode_log_segment_bounded([record], byte_size(json)) == {:ok, json}
    assert NIF.encode_log_segment_bounded([record], 10_000) == {:error, :query_result_limit}
    assert NIF.encode_log_segment_bounded([], 1) == {:error, :query_result_limit}
    assert NIF.encode_log_segment_bounded([], 2) == {:ok, "[]"}
  end
end
