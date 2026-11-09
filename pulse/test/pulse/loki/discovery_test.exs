defmodule Pulse.Loki.DiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.Loki.Discovery
  alias Pulse.Record.Log
  alias Pulse.Storage.Memory

  @values ["prod", "staging", "", "a\"b\\c", "ünï", "api-1", "web-1"]
  @keys ["namespace", "pod", "container", "level", "service_name", "esc\"key"]

  defp random_record(ts) do
    resource =
      for key <- Enum.take_random(@keys, :rand.uniform(length(@keys))), into: %{} do
        case :rand.uniform(6) do
          1 -> {key, :rand.uniform(9)}
          _ -> {key, Enum.random(@values)}
        end
      end

    %Log{
      timestamp_ns: ts,
      service: Enum.random([nil, "", "api", "web"]),
      severity_text: Enum.random([nil, "", "info", "error"]),
      body: "line #{ts}",
      resource: resource
    }
  end

  defp random_matchers do
    for _ <- 1..:rand.uniform(3)//1, :rand.uniform(2) == 1 do
      name = Enum.random(@keys ++ ["service", "detected_level"])
      value = Enum.random(@values)

      case Enum.random([:eq, :neq, :re, :nre]) do
        op when op in [:re, :nre] -> {name, op, StreamMatchers.anchor(Enum.random(["prod", "api", "w", ""]) <> ".*")}
        op -> {name, op, value}
      end
    end
  end

  defp native(blob, mode, key, opts) do
    {:ok, state} =
      NIF.log_discovery_new(mode, key, opts[:start_ts], opts[:end_ts], opts[:service], opts[:matchers])

    {:ok, _rows} = NIF.log_discovery_add(state, blob)
    NIF.log_discovery_finish(state)
  end

  # The reference matches every record with a dirty-CPU regex NIF, so under CI
  # contention it queues behind other tests' native work. Keep all 180
  # comparisons without the ordinary one-minute test budget.
  @tag timeout: 300_000
  test "native discovery agrees with the record-backed reference on random streams" do
    tenant = "discovery-parity-#{System.unique_integer([:positive])}"
    records = for ts <- 1..400, do: random_record(ts)
    :ok = Memory.append(:logs, tenant, records)
    {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet(records)

    for _ <- 1..60 do
      opts = [
        start_ts: Enum.random([0, 50, 100]),
        end_ts: Enum.random([100, 300, 400]),
        service: Enum.random([nil, "api"]),
        matchers: random_matchers()
      ]

      for {mode, key} <- [{"names", ""}, {"values", Enum.random(@keys)}, {"series", ""}] do
        reference_opts = if opts[:service], do: opts, else: Keyword.delete(opts, :service)
        {:ok, expected} = Discovery.reference(Memory, tenant, String.to_existing_atom(mode), key, reference_opts)
        {:ok, actual} = native(blob, mode, key, opts)

        assert Pulse.JSON.decode!(actual) == Pulse.JSON.decode!(expected),
               "mode=#{mode} key=#{inspect(key)} opts=#{inspect(opts)}"
      end
    end
  end

  test "dictionaries are sorted, deduplicated and project service_name" do
    records = [
      %Log{timestamp_ns: 1, service: "api", resource: %{"namespace" => "prod", "pod" => "b"}},
      %Log{timestamp_ns: 2, service: "api", resource: %{"namespace" => "prod", "pod" => "a"}},
      %Log{timestamp_ns: 3, service: "api", resource: %{"namespace" => "prod", "pod" => "a"}}
    ]

    {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet(records)
    opts = [start_ts: 0, end_ts: 10, service: nil, matchers: []]

    assert {:ok, ~s(["namespace","pod","service_name"])} = native(blob, "names", "", opts)
    assert {:ok, ~s(["a","b"])} = native(blob, "values", "pod", opts)

    assert {:ok, series} = native(blob, "series", "", opts)

    assert Pulse.JSON.decode!(series) == [
             %{"namespace" => "prod", "pod" => "a", "service_name" => "api"},
             %{"namespace" => "prod", "pod" => "b", "service_name" => "api"}
           ]
  end

  test "invalid requests fall back instead of guessing" do
    assert :fallback = NIF.log_discovery_new("bogus", "", 0, 1, nil, [])
    assert :fallback = NIF.log_discovery_new("values", "", 0, 1, nil, [])
    assert :fallback = NIF.log_discovery_new("names", "", 2, 1, nil, [])
    assert :fallback = NIF.log_discovery_new("names", "", 0, 1, nil, [{"pod", :re, "("}])
  end
end
