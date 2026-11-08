defmodule Pulse.OTLP.JSONFieldsTest do
  use Pulse.Test.Case, async: true

  alias Elixir.JSON.DecodeError
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.{JSON, JSONReference}
  alias Pulse.OTLP.Logs

  @directory "test/fixtures/otlp/json_fields"

  test "frozen public field decisions and producer inputs match their checksum index" do
    manifest = @directory |> Path.join("checksums.json") |> File.read!() |> Pulse.JSON.decode!()
    assert manifest["otlp"] == "v1.9.0"
    assert manifest["google_protobuf"] == "v1.36.11"
    assert map_size(manifest["files"]) == 4

    for {path, expected} <- manifest["files"] do
      bytes = File.read!(Path.join(@directory, path))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected, path
    end
  end

  test "public ProtoJSON duplicate-field decisions agree across native and independent reference paths" do
    rows = @directory |> Path.join("cases.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(rows) == 704
    assert Enum.count(rows, & &1["accepted"]) == 355

    for row <- rows do
      signal = signal(row["signal"])
      native = NIF.otlp_json_decode_scoped(row["input"], signal)

      if row["accepted"] do
        reference = JSONReference.decode!(row["input"], signal)
        assert bits(JSON.decode!(row["input"], signal)) == bits(reference), row["name"]

        case native do
          {:ok, value} -> assert bits(value) == bits(reference), row["name"]
          :fallback -> assert row["name"] =~ ~r/(unknown|foreign-root)/, row["name"]
        end
      else
        assert native == :fallback, row["name"]
        assert_raise ArgumentError, ~r/duplicate OTLP JSON field/, fn -> JSONReference.decode!(row["input"], signal) end
        assert_raise ArgumentError, ~r/duplicate OTLP JSON field/, fn -> JSON.decode!(row["input"], signal) end
      end
    end
  end

  test "exponential point scalar duplicates cannot bypass the independent fallback" do
    for field <- ~w(sum min max zeroThreshold), second <- ["2", "null"] do
      body =
        ~s({"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"exponentialHistogram":{"dataPoints":[{"#{field}":1,"#{field}":#{second}}]}}]}]}]})

      assert :fallback = NIF.otlp_json_decode_scoped(body, :metrics)
      assert_raise ArgumentError, ~r/duplicate OTLP JSON field/, fn -> JSONReference.decode!(body, :metrics) end
      assert_raise ArgumentError, ~r/duplicate OTLP JSON field/, fn -> JSON.decode!(body, :metrics) end
    end
  end

  test "additional scalar fields follow the same rejection rules as containers" do
    for {signal, body} <- [
          {:logs,
           ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"boolValue":false,"boolValue":true}}]}]}]})},
          {:logs, ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"bytesValue":"","bytesValue":""}}]}]}]})},
          {:metrics, ~s({"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"description":"a","description":"b"}]}]}]})},
          {:traces, ~s({"resourceSpans":[{"scopeSpans":[{"spans":[{"status":{"code":0,"code":1}}]}]}]})}
        ] do
      assert :fallback = NIF.otlp_json_decode_scoped(body, signal)
      assert_raise ArgumentError, fn -> JSON.decode!(body, signal) end
    end
  end

  test "unknown message objects cannot acquire a schema from their field names" do
    text = ~S({"resourceLogs":[],"future":{"resourceLogs":[],"resourceLogs":[],"intValue":7,"intValue":8}})
    assert :fallback = NIF.otlp_json_decode_scoped(text, :logs)
    assert JSON.decode!(text, :logs)["future"]["intValue"] == 7
    assert bits(JSON.decode!(text, :logs)) == bits(JSONReference.decode!(text, :logs))
    # The general JSON library still uses the built-in first-key contract.
    assert Pulse.JSON.decode!(~s({"kind":1,"kind":2})) == %{"kind" => 1}
  end

  test "opaque valid numeric tokens remain nodes with numeric admission costs" do
    body =
      ~s({"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"1","attributes":[{"key":"a","value":{"future":1e1000000}}]}]}]}]})

    assert :fallback = NIF.otlp_json_decode_scoped(body, :logs)
    value = JSON.decode!(body, :logs)
    assert bits(value) == bits(JSONReference.decode!(body, :logs))
    # key a + unknown field name future + one numeric scalar = 1 + 6 + 8.
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_attribute_bytes: 14)
    assert {:error, :attributes_too_large} = Logs.decode(value)
    Pulse.Runtime.put_env(:pulse, Pulse.IngestLimits, max_attribute_bytes: 15)
    assert {:ok, [log], 0} = Logs.decode(value)
    assert log.attributes == %{"a" => nil}

    assert bits(JSON.decode!(String.replace(body, "1e1000000", "1e-1000000"), :logs)) ==
             bits(JSONReference.decode!(String.replace(body, "1e1000000", "1e-1000000"), :logs))

    assert_raise DecodeError, fn -> JSON.decode!(String.replace(body, "1e1000000", "NaN"), :logs) end
  end

  test "known duplicate rejection cannot be evaded by forcing native fallback first" do
    text =
      ~S({"future":0,"future":1,"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"intValue":"7","int\u0056alue":"8"}}]}]}]})

    assert :fallback = NIF.otlp_json_decode_scoped(text, :logs)
    assert_raise ArgumentError, fn -> JSON.decode!(text, :logs) end
    assert_raise ArgumentError, fn -> JSONReference.decode!(text, :logs) end
  end

  defp signal("logs"), do: :logs
  defp signal("metrics"), do: :metrics
  defp signal("traces"), do: :traces
  defp bits(value), do: :erlang.term_to_binary(value, [:deterministic])
end
