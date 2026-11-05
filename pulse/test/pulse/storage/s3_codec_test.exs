defmodule Pulse.Storage.S3CodecTest do
  # The S3 adapter encodes and decodes log segments as Apache Parquet in
  # Rust (`Pulse.Codec.NIF.{encode,decode}_log_segment_parquet`). There
  # is no Elixir Parquet reference to cross-check against, so this file
  # exercises the shape and stability of the round-trip: encoding a batch
  # and decoding it back produces a set of records that re-encodes to a
  # stable segment on the second pass, and the filter surface behaves
  # the same at the NIF boundary as it does on the returned list.
  #
  # The `(:plain, :array)` NDJSON encoder is left in place for
  # `Pulse.MCP.Tools` — its test lives at the bottom.
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log
  alias Pulse.Storage.S3
  alias Pulse.Test.RandomTerms

  defp canonicalize(records) do
    Enum.sort_by(records, &:erlang.term_to_binary(&1, [:deterministic]))
  end

  describe "encode_segment/1" do
    test "encode → decode → encode → decode is idempotent from the first decode on" do
      # The first pass through the codec normalises the input (atom map
      # keys stringified, charlists→strings, structs decomposed). Every
      # pass after that is a pure round-trip.
      for _ <- 1..200 do
        records = RandomTerms.logs(:rand.uniform(40))
        {:ok, payload, min_ts, max_ts} = S3.encode_segment(:logs, records)
        {:ok, decoded1} = S3.decode_segment(:logs, payload, nil, nil, [])
        {:ok, payload2, min_ts2, max_ts2} = S3.encode_segment(:logs, decoded1)
        {:ok, decoded2} = S3.decode_segment(:logs, payload2, nil, nil, [])

        assert canonicalize(decoded1) == canonicalize(decoded2)
        assert min_ts == min_ts2
        assert max_ts == max_ts2
        assert length(decoded1) == length(records)
      end
    end

    test "bounded footer statistics preserve long Unicode data and exact time filters" do
      prefix = String.duplicate("界🌍", 1000)

      records =
        for ts <- [10, 20],
            do: %Log{
              timestamp_ns: ts,
              service: prefix <> "#{ts}",
              body: prefix <> "#{ts}",
              attributes: %{"context" => prefix},
              resource: %{"long" => prefix}
            }

      assert {:ok, payload, 10, 20} = S3.encode_segment(:logs, records)
      assert {:ok, decoded} = S3.decode_segment(:logs, payload, nil, nil, [])
      assert canonicalize(decoded) == canonicalize(records)
      assert {:ok, [selected]} = S3.decode_segment(:logs, payload, 20, 20, service: prefix <> "20")
      assert selected == List.last(records)
      assert {:ok, []} = S3.decode_segment(:logs, payload, 21, nil, [])
    end

    test "preserves the caller's timestamp bounds" do
      records = for ts <- [50, 10, 30], do: %Log{timestamp_ns: ts}
      assert {:ok, _payload, 10, 50} = S3.encode_segment(:logs, records)
    end

    test "an empty batch encodes to a valid segment with zero bounds" do
      assert {:ok, payload, 0, 0} = S3.encode_segment(:logs, [])
      # An empty Parquet file with the schema round-trips to no records.
      assert {:ok, []} = S3.decode_segment(:logs, payload, nil, nil, [])
    end

    test "nil or empty attributes and resource decode as empty maps" do
      records = [%Log{timestamp_ns: 1, attributes: nil, resource: %{}}]
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      assert {:ok, [decoded]} = S3.decode_segment(:logs, payload, nil, nil, [])
      assert decoded.attributes == %{}
      assert decoded.resource == %{}
    end

    test "colliding stringified attribute keys surface as an attribute-key-collision error" do
      records = [%Log{timestamp_ns: 1, attributes: %{:a => 1, "a" => 2}}]
      assert {:error, {:attribute_key_collision, _}} = S3.encode_segment(:logs, records)
    end

    test "a non-UTF-8 body surfaces as a Parquet encoder error" do
      records = [%Log{timestamp_ns: 1, body: <<0xFF>>}]
      assert {:error, {:encode_failed, _}} = S3.encode_segment(:logs, records)
    end

    test "a JSON-unencodable body value (reference) surfaces as a Parquet encoder error" do
      records = [%Log{timestamp_ns: 1, body: make_ref()}]
      assert {:error, {:encode_failed, _}} = S3.encode_segment(:logs, records)
    end

    test "false JSON bodies survive encoding without becoming nil" do
      records = [%Log{timestamp_ns: 1, body: false}, %Log{timestamp_ns: 2, body: nil}]
      assert {:ok, payload, 1, 2} = S3.encode_segment(:logs, records)
      assert {:ok, ^records} = S3.decode_segment(:logs, payload, nil, nil, [])
    end

    test "JSON fields cannot be written deeper than the segment decoder can read" do
      readable = Enum.reduce(1..200, "value", fn _, value -> [value] end)

      record = %Log{
        timestamp_ns: 1,
        body: readable,
        attributes: %{"nested" => readable},
        resource: %{"nested" => readable}
      }

      assert {:ok, payload, 1, 1} = S3.encode_segment(:logs, [record])
      assert {:ok, [^record]} = S3.decode_segment(:logs, payload, nil, nil, [])

      too_deep = Enum.reduce(1..300, "value", fn _, value -> [value] end)

      for field <- [:body, :attributes, :resource] do
        value = if field == :body, do: too_deep, else: %{"nested" => too_deep}
        invalid = Map.put(%Log{timestamp_ns: 1}, field, value)
        assert {:error, {:encode_failed, _}} = S3.encode_segment(:logs, [invalid])
      end
    end

    test "an out-of-range integer timestamp surfaces as a Parquet encoder error" do
      # Parquet's timestamp column is Int64; anything past 2^63 - 1 must
      # not be silently truncated.
      records = [%Log{timestamp_ns: 123_456_789_012_345_678_901_234_567_890}]
      assert {:error, {:encode_failed, _}} = S3.encode_segment(:logs, records)
    end
  end

  describe "decode_segment/4" do
    test "expanded dictionary buffers, not compressed bytes or filtered output, consume the decode budget" do
      body = String.duplicate("x", 100_000)
      records = for ts <- 1..20, do: %Log{timestamp_ns: ts, body: body}
      assert {:ok, payload, 1, 20} = S3.encode_segment(:logs, records)
      assert byte_size(payload) < 20_000
      opts = [max_records: 20, max_decoded_bytes: 4_194_304]
      assert {:ok, ^records, charged} = S3.decode_log_segment_bounded(payload, nil, nil, opts)
      assert charged >= 2_000_000
      assert charged < 2_100_000
      assert {:ok, ^records} = S3.decode_segment(:logs, payload, nil, nil, opts)

      opts = Keyword.put(opts, :max_decoded_bytes, 1_048_576)
      assert {:error, :query_decoded_limit} = S3.decode_segment(:logs, payload, nil, nil, opts)
      # Only one matching row does not make decoding the other rows free.
      assert {:error, :query_decoded_limit} = S3.decode_log_segment_bounded(payload, 20, 20, opts)
      assert {:ok, [], 0} = S3.decode_log_segment_bounded(payload, 21, nil, opts)
    end

    test "bounded decoding handles ordinary log rows larger than the Sentry wire cap" do
      # Historical segments can exceed the new normalized write ceiling.
      # JSON escaping produces 3 MB per row, dictionary-compressed on disk.
      # Preserve bounded reads without weakening the 16 MiB encoder limit.
      row = %Log{timestamp_ns: 1, service: "api", body: String.duplicate(<<0>>, 500_000)}
      assert {:error, :payload_too_large} = S3.encode_segment(:logs, List.duplicate(row, 32))
      payload = File.read!(Path.expand("../../fixtures/logs/legacy_expanded_log.parquet", __DIR__))
      assert byte_size(payload) < 10_000
      opts = [max_decoded_bytes: 33_554_432, matchers: [{"error_source", :eq, "sentry"}]]
      assert {:error, :query_decoded_limit} = S3.decode_log_segment_bounded(payload, nil, nil, opts)

      assert {:ok, [], charged} =
               S3.decode_log_segment_bounded(payload, nil, nil, Keyword.put(opts, :max_decoded_bytes, 134_217_728))

      assert charged >= 96_000_000

      # A genuinely small window/segment containing the large row still works;
      # the fix must not impose a new 1 MiB per-log-row compatibility limit.
      assert {:ok, single, 1, 1} = S3.encode_segment(:logs, [row])

      assert {:ok, [^row], bytes} =
               S3.decode_log_segment_bounded(single, nil, nil, max_decoded_bytes: 4_194_304)

      assert bytes >= 3_000_000
    end

    test "a corrupt footer cannot preallocate output from an enormous claimed row count" do
      # One physical row, but the footer claims 2^36 rows (512 GiB of term
      # slots). The fixture generator verifies that metadata is readable.
      payload = File.read!(Path.expand("../../fixtures/logs/corrupt_footer.parquet", __DIR__))
      assert {:error, {:decode_failed, _}} = S3.decode_segment(:logs, payload, nil, nil, [])
    end

    test "reads back everything a segment holds when no filter is set" do
      records = for i <- 1..30, do: %Log{timestamp_ns: i * 1000, service: "svc#{rem(i, 3)}"}
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      assert {:ok, decoded} = S3.decode_segment(:logs, payload, nil, nil, [])
      assert length(decoded) == 30
    end

    test "time-range filter drops records outside [start_ts, end_ts]" do
      records = for ts <- 1..10, do: %Log{timestamp_ns: ts, service: "svc"}
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      {:ok, kept} = S3.decode_segment(:logs, payload, 3, 7, [])
      assert Enum.sort(Enum.map(kept, & &1.timestamp_ns)) == [3, 4, 5, 6, 7]
    end

    test "half-open time filters work with only one bound set" do
      records = for ts <- 1..5, do: %Log{timestamp_ns: ts}
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      {:ok, from_3} = S3.decode_segment(:logs, payload, 3, nil, [])
      assert Enum.sort(Enum.map(from_3, & &1.timestamp_ns)) == [3, 4, 5]
      {:ok, upto_3} = S3.decode_segment(:logs, payload, nil, 3, [])
      assert Enum.sort(Enum.map(upto_3, & &1.timestamp_ns)) == [1, 2, 3]
    end

    test "service filter drops records with a different service" do
      records = [
        %Log{timestamp_ns: 1, service: "svc1"},
        %Log{timestamp_ns: 2, service: "svc2"},
        %Log{timestamp_ns: 3, service: "svc1"}
      ]

      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      {:ok, kept} = S3.decode_segment(:logs, payload, nil, nil, service: "svc1")
      assert Enum.sort(Enum.map(kept, & &1.timestamp_ns)) == [1, 3]
    end

    test "repeated resource maps share immutable terms without confusing metadata transitions" do
      resources = [%{}, %{"region" => "east"}, %{"region" => "east"}, %{}, %{"region" => "west"}]

      records =
        resources
        |> Enum.with_index(1)
        |> Enum.map(fn {resource, ts} -> %Log{timestamp_ns: ts, service: "api", resource: resource} end)

      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      {:ok, decoded} = S3.decode_segment(:logs, payload, nil, nil, [])
      assert Enum.map(decoded, & &1.resource) == resources
      assert :erts_debug.same(Enum.at(decoded, 1).resource, Enum.at(decoded, 2).resource)
      {:ok, filtered} = S3.decode_segment(:logs, payload, 3, 5, [])
      assert Enum.map(filtered, & &1.resource) == Enum.drop(resources, 2)
    end

    test "JSON object keys are shared across rows and column documents without changing values" do
      records =
        for i <- 1..20 do
          %Log{
            timestamp_ns: i,
            body: %{"shared_key" => i},
            attributes: %{"shared_key" => "value-#{i}"},
            resource: %{"shared_key" => i * 2}
          }
        end

      {:ok, blob, _, _} = S3.encode_segment(:logs, records)
      {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
      assert decoded == records
      [first, second | _] = decoded
      assert :erts_debug.same(hd(Map.keys(first.body)), hd(Map.keys(second.attributes)))
      assert :erts_debug.same(hd(Map.keys(first.body)), hd(Map.keys(second.resource)))
    end

    test "key interning remains correct past its bounded capacity and for escaped or long keys" do
      records =
        for i <- 1..200 do
          %Log{timestamp_ns: i, attributes: %{"key-#{i}" => i, "escaped\nkey" => "v", String.duplicate("x", 40) => i}}
        end

      {:ok, blob, _, _} = S3.encode_segment(:logs, records)
      {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
      assert decoded == records
    end

    test "record sharing preserves duplicates and every changed field" do
      base = %Log{timestamp_ns: 1, service: "api", body: "message", resource: %{"region" => "east"}}

      records = [
        base,
        base,
        %{base | attributes: %{"request_id" => "new"}},
        %{base | body: "different"},
        %{base | trace_id: "trace", span_id: "span", severity_text: "ERROR", severity_number: 17}
      ]

      {:ok, blob, _, _} = S3.encode_segment(:logs, records)
      {:ok, decoded} = S3.decode_segment(:logs, blob, nil, nil, [])
      assert decoded == records
      assert :erts_debug.same(hd(decoded), Enum.at(decoded, 1))
      assert :erts_debug.same(hd(decoded).service, List.last(decoded).service)
    end

    test "drops nil-timestamp records under any time filter" do
      records = [%Log{timestamp_ns: nil, body: "x"}, %Log{timestamp_ns: 5, body: "y"}]
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      {:ok, all} = S3.decode_segment(:logs, payload, nil, nil, [])
      assert length(all) == 2
      {:ok, kept} = S3.decode_segment(:logs, payload, 0, nil, [])
      assert match?([%Log{timestamp_ns: 5}], kept)
    end

    test "row-group time pruning skips a segment entirely outside the range" do
      records = for ts <- 100..200, do: %Log{timestamp_ns: ts, service: "svc"}
      {:ok, payload, _, _} = S3.encode_segment(:logs, records)
      # Every timestamp in [100, 200]; asking for [500, 600] must decode
      # to nothing without materialising any Erlang record term.
      assert {:ok, []} = S3.decode_segment(:logs, payload, 500, 600, [])
    end

    test "non-parquet input surfaces as a Parquet decoder error" do
      assert {:error, {:decode_failed, _}} = S3.decode_segment(:logs, "not-parquet", nil, nil, [])
    end

    test "an empty binary is not a valid Parquet file" do
      assert {:error, {:decode_failed, _}} = S3.decode_segment(:logs, "", nil, nil, [])
    end
  end

  describe "MCP tools' JSON-array encoder (kept alongside the Parquet path)" do
    test "matches the field maps for random batches" do
      # `Pulse.MCP.Tools.encode_records/1` still calls this NIF to
      # serialise query results back to the model.
      for _ <- 1..50 do
        records = RandomTerms.logs(:rand.uniform(20))
        assert {:ok, json, _, _, _} = NIF.encode_log_segment(records, :plain, :array)

        expected =
          records
          |> Enum.map(&Map.from_struct/1)
          |> JSON.encode!()
          |> JSON.decode!()

        assert JSON.decode!(json) == expected
      end
    end
  end
end
