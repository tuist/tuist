defmodule Pulse.IngestLimitsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.IngestLimits

  setup do
    Pulse.Runtime.delete_env(:pulse, IngestLimits)
    :ok
  end

  test "defaults and native options agree" do
    assert IngestLimits.native_options() == {10_000, 128, 256, 16_384, 65_536}
    assert IngestLimits.config().max_depth == 16
    assert IngestLimits.config().max_nodes == 1_024
  end

  test "non-positive and non-integer configuration cannot disable a budget" do
    for value <- [0, -1, nil, :infinity, 1.5, 2_147_483_648] do
      Pulse.Runtime.put_env(:pulse, IngestLimits, max_records: value)
      assert_raise ArgumentError, fn -> IngestLimits.config() end
    end
  end

  test "runtime environment overrides are validated at startup" do
    # runtime.exs reads variables through the test-owned runtime environment,
    # so this never touches the OS environment of the shared test VM.
    name = "PULSE_INGEST_MAX_RECORDS"
    path = Path.expand("../../config/runtime.exs", __DIR__)

    Pulse.Runtime.put_env(name, "12")
    config = Config.Reader.read!(path, env: :test, target: :host)
    assert config[:pulse][IngestLimits][:max_records] == 12

    for value <- ["0", "-1", "12junk", "", "2147483648"] do
      Pulse.Runtime.put_env(name, value)
      assert_raise RuntimeError, fn -> Config.Reader.read!(path, env: :test, target: :host) end
    end
  end

  test "nested Loki metadata has exact depth and node boundaries" do
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_depth: 2, max_nodes: 3)
    payload = loki(%{"a" => %{"b" => "v"}})
    assert IngestLimits.validate(:loki, payload) == :ok
    assert IngestLimits.validate(:loki, loki(%{"a" => %{"b" => ["v"]}})) == {:error, :attributes_too_large}
    assert IngestLimits.validate(:loki, loki(%{"a" => %{"b" => "v", "c" => "v"}})) == {:error, :attributes_too_large}
  end

  test "OTLP key and value limits are independent" do
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_key_bytes: 4, max_value_bytes: 1)
    record = %{"attributes" => [%{"key" => "aaaa", "value" => %{"stringValue" => "v"}}]}
    assert IngestLimits.validate(:otlp, request(record)) == :ok
  end

  test "a one-record OTLP budget still allows its resource and scope groups" do
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_records: 1)
    assert IngestLimits.validate(:otlp, request(%{})) == :ok
  end

  test "OTLP arrays and nested key-value lists are bounded before AnyValue conversion" do
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_depth: 2, max_nodes: 4, max_attributes: 2)
    value = %{"arrayValue" => %{"values" => [%{"stringValue" => "v"}]}}
    assert IngestLimits.validate(:otlp, otlp(value)) == :ok
    nested = %{"arrayValue" => %{"values" => [value]}}
    assert IngestLimits.validate(:otlp, otlp(nested)) == {:error, :attributes_too_large}
    wide = %{"arrayValue" => %{"values" => List.duplicate(%{"stringValue" => "v"}, 2)}}
    assert IngestLimits.validate(:otlp, otlp(wide)) == {:error, :attributes_too_large}

    Pulse.Runtime.put_env(:pulse, IngestLimits, max_attributes: 2)
    pairs = List.duplicate(%{"key" => "a", "value" => %{"stringValue" => "v"}}, 3)

    assert IngestLimits.validate(:otlp, otlp(%{"kvlistValue" => %{"values" => pairs}})) ==
             {:error, :attributes_too_large}
  end

  test "structured OTLP bodies are bounded but ordinary messages are not attribute values" do
    value = %{"arrayValue" => %{"values" => [%{"stringValue" => "v"}]}}
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_depth: 1)
    assert IngestLimits.validate(:otlp, body(value)) == :ok

    assert IngestLimits.validate(:otlp, body(%{"arrayValue" => %{"values" => [value]}})) ==
             {:error, :attributes_too_large}

    assert IngestLimits.validate(:otlp, body(%{"stringValue" => String.duplicate("a", 16_385)})) == :ok
  end

  test "deep malformed AnyValue keys and values still consume budgets" do
    Pulse.Runtime.put_env(:pulse, IngestLimits, max_depth: 2)

    assert IngestLimits.validate(:otlp, otlp(%{"unknown" => %{"a" => %{"b" => "v"}}})) ==
             {:error, :attributes_too_large}
  end

  defp loki(metadata) do
    %{"streams" => [%{"stream" => %{}, "values" => [["1", "hello", metadata]]}]}
  end

  defp otlp(value) do
    request(%{"attributes" => [%{"key" => "a", "value" => value}]})
  end

  defp body(value), do: request(%{"body" => value})
  defp request(record), do: %{"resourceLogs" => [%{"scopeLogs" => [%{"logRecords" => [record]}]}]}
end
