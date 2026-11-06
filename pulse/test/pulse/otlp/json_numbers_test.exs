defmodule Pulse.OTLP.JSONNumbersTest do
  use Pulse.Test.Case, async: true

  alias Elixir.JSON.DecodeError
  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.{JSON, JSONReference, Logs, Metrics, Traces, Value}
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @directory "test/fixtures/otlp/numbers"
  @invalid_json ["01", "+1", ".0", "1.", "NaN", "Infinity"]

  test "frozen numeric inputs and public captures match their checksum index" do
    manifest = @directory |> Path.join("checksums.json") |> File.read!() |> Pulse.JSON.decode!()
    assert manifest["otlp"] == "v1.9.0"
    assert manifest["google_protobuf"] == "v1.36.11"
    assert map_size(manifest["files"]) == 20

    for {path, expected} <- manifest["files"] do
      bytes = File.read!(Path.join(@directory, path))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected, path
    end
  end

  test "public ProtoJSON numeric decisions and exact values match native and independent reference paths" do
    rows = @directory |> Path.join("cases.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(rows) == 156

    for row <- rows do
      {body, extract, low, high} = candidate(row["kind"], row["literal"])

      if row["literal"] in @invalid_json do
        assert :fallback = NIF.otlp_json_decode(body)
        assert_raise DecodeError, fn -> JSON.decode!(body) end
        assert_raise DecodeError, fn -> JSONReference.decode!(body) end
      else
        # Ensure the native path actually answered, including invalid numeric
        # values whose representation must not underflow to a valid integer 0.
        assert {:ok, native} = NIF.otlp_json_decode(body)
        assert bits(native) == bits(JSONReference.decode!(body)), inspect(row)
        actual = Value.integer(extract.(native), low, high)

        if row["accepted"] do
          assert actual == {:ok, String.to_integer(row["expected"])}, inspect(row)
        else
          assert actual == :error, inspect(row)
        end
      end
    end
  end

  test "public full signal requests retain exact originals and signed zero through native Parquet" do
    for {name, decoder, signal, count} <- [
          {"logs", Logs, :logs, 1},
          {"metrics", Metrics, :metrics, 7},
          {"traces", Traces, :traces, 1}
        ] do
      input = File.read!(Path.join(@directory, name <> "-input.json"))
      canonical = File.read!(Path.join(@directory, name <> "-canonical.json"))
      assert {:ok, native} = NIF.otlp_json_decode(input)
      assert bits(native) == bits(JSONReference.decode!(input))
      assert {:ok, records, 0} = decoder.decode(native)
      assert length(records) == count
      assert {:ok, expected, 0} = decoder.decode(JSON.decode!(canonical))
      assert {:ok, wire, 0} = decoder.decode_protobuf(File.read!(Path.join(@directory, name <> ".protobuf")))
      assert bits(records) == bits(expected)
      assert bits(records) == bits(wire)
      assert Enum.all?(records, &(&1.timestamp_ns == 1_700_000_000_123_456_789))
      assert {:ok, blob, _, _} = S3.encode_segment(signal, records)
      assert {:ok, decoded} = S3.decode_segment(signal, blob, nil, nil, [])
      assert Enum.sort(Enum.map(decoded, &bits(&1.otlp))) == Enum.sort(Enum.map(records, &bits(&1.otlp)))
    end

    assert {:ok, [log], 0} =
             @directory |> Path.join("logs-input.json") |> File.read!() |> JSON.decode!() |> Logs.decode()

    assert log.body == 9_007_199_254_740_993
    assert log.otlp["body"] == %{"intValue" => "9007199254740993"}
    assert <<log.attributes["zero"]::float-64>> == <<0x8000000000000000::64>>
  end

  test "randomized exact lexical conversions always answer natively and match the Elixir reference" do
    :rand.seed(:exsss, {81, 16, 128})

    for _ <- 1..300 do
      n = :rand.uniform(18_446_744_073_709_551_615) - 1
      n = if rem(n, 2) == 0, do: n, else: -div(n, 2)
      zeroes = :rand.uniform(10)
      text = Integer.to_string(n) <> String.duplicate("0", zeroes) <> "e-" <> Integer.to_string(zeroes)
      {body, extract, _, _} = candidate("int64", text)
      assert {:ok, native} = NIF.otlp_json_decode(body)
      assert extract.(native) == n
      assert bits(native) == bits(JSONReference.decode!(body))
    end
  end

  test "scope and escaped keys distinguish integral fields, double fields and unknown objects" do
    text =
      ~S({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"int\u0056alue":9007199254740993.0}}]}]}],"unknown":{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"intValue":9007199254740993.0}}]}]}]}})

    assert {:ok, native} = NIF.otlp_json_decode(text)
    assert bits(native) == bits(JSONReference.decode!(text))

    assert get_in(native, [
             "resourceLogs",
             Access.at(0),
             "scopeLogs",
             Access.at(0),
             "logRecords",
             Access.at(0),
             "body",
             "intValue"
           ]) == 9_007_199_254_740_993

    assert is_float(
             get_in(native, [
               "unknown",
               "resourceLogs",
               Access.at(0),
               "scopeLogs",
               Access.at(0),
               "logRecords",
               Access.at(0),
               "body",
               "intValue"
             ])
           )

    for token <- ["-0", "-0.0", "-0e0", "1e-0", "1.5e-0"] do
      {body, _, _, _} = candidate("int64", token)
      body = String.replace(body, "intValue", "doubleValue")
      assert {:ok, native} = NIF.otlp_json_decode(body)
      assert bits(native) == bits(JSONReference.decode!(body))
    end

    assert Pulse.JSON.decode!("-0") === 0
    assert is_float(Pulse.JSON.decode!("9007199254740993.0"))
  end

  test "fallback retains exact integers without changing ordinary JSON errors or duplicate-key behavior" do
    {body, extract, _, _} = candidate("int64", "9007199254740993.0")
    body = String.replace(body, ~s("body":), ~s("name":"first","name":"second","body":))
    assert :fallback = NIF.otlp_json_decode(body)
    assert extract.(JSON.decode!(body)) == 9_007_199_254_740_993
    assert bits(JSON.decode!(body)) == bits(JSONReference.decode!(body))

    for suffix <- [" x", "{}", <<194, 160>>] do
      assert_raise DecodeError, fn -> JSON.decode!(body <> suffix) end
    end

    for text <- [~S({"x":"escaped \" -0,"}), ~S({"x":"\\","n":-0}), "-0", "[-0,1e-0,1.5e-0]"] do
      assert bits(JSON.decode!(text)) == bits(JSONReference.decode!(text))
    end

    # Invalid Unicode must retain the built-in parser's error, not be repaired.
    assert_raise DecodeError, fn -> JSON.decode!(~S({"x":"bad\uD800"})) end
  end

  test "public double zero bits survive integer-mantissa exponents and native fallback" do
    rows = @directory |> Path.join("floating-zeros.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(rows) == 11

    for row <- rows do
      {body, _, _, _} = candidate("int64", row["literal"])
      body = String.replace(body, "intValue", "doubleValue")
      value = JSON.decode!(body)
      assert bits(value) == bits(JSONReference.decode!(body))

      zero =
        get_in(value, [
          "resourceLogs",
          Access.at(0),
          "scopeLogs",
          Access.at(0),
          "logRecords",
          Access.at(0),
          "body",
          "doubleValue"
        ])

      assert Base.encode16(<<zero::float-64>>, case: :lower) == row["bits"]
    end
  end

  test "numeric admission stays one scalar and eight bytes, never the cheaper string spelling" do
    Runtime.put_env(:pulse, IngestLimits, max_attribute_bytes: 8)

    for token <- ["0", "0.0", "1e0", "1e-1000"] do
      {body, _, _, _} = candidate("int64", token)

      body =
        String.replace(
          body,
          ~s("body":{"intValue":#{token}}),
          ~s("attributes":[{"key":"a","value":{"intValue":#{token}}}])
        )

      assert {:error, :attributes_too_large} = body |> JSON.decode!() |> Logs.decode()
    end

    Runtime.put_env(:pulse, IngestLimits, max_attribute_bytes: 9)
    {body, _, _, _} = candidate("int64", "1e-1000")
    assert {:ok, [], 1} = body |> JSON.decode!() |> Logs.decode()
  end

  defp bits(term), do: :erlang.term_to_binary(term, [:deterministic])

  defp candidate("int64", literal) do
    body = ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"1","body":{"intValue":#{literal}}}]}]}]})

    {body,
     &get_in(&1, [
       "resourceLogs",
       Access.at(0),
       "scopeLogs",
       Access.at(0),
       "logRecords",
       Access.at(0),
       "body",
       "intValue"
     ]), -9_223_372_036_854_775_808, 9_223_372_036_854_775_807}
  end

  defp candidate("uint64", literal) do
    body =
      ~s({"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"histogram":{"dataPoints":[{"count":#{literal}}]}}]}]}]})

    {body,
     &get_in(&1, [
       "resourceMetrics",
       Access.at(0),
       "scopeMetrics",
       Access.at(0),
       "metrics",
       Access.at(0),
       "histogram",
       "dataPoints",
       Access.at(0),
       "count"
     ]), 0, 18_446_744_073_709_551_615}
  end

  defp candidate("uint32", literal) do
    body = ~s({"resourceLogs":[{"resource":{"droppedAttributesCount":#{literal}}}]})
    {body, &get_in(&1, ["resourceLogs", Access.at(0), "resource", "droppedAttributesCount"]), 0, 4_294_967_295}
  end

  defp candidate("enum", literal) do
    body = ~s({"resourceSpans":[{"scopeSpans":[{"spans":[{"kind":#{literal}}]}]}]})

    {body, &get_in(&1, ["resourceSpans", Access.at(0), "scopeSpans", Access.at(0), "spans", Access.at(0), "kind"]),
     -2_147_483_648, 2_147_483_647}
  end
end
