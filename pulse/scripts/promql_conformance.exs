# Run with MIX_ENV=test mix run scripts/promql_conformance.exs [promtool binary].
# Offline numerical oracle: promtool independently evaluates Pulse's expected
# values from identical samples. No production, scrape, or network access.
alias Pulse.PromQL.Conformance
alias Pulse.PromQL.Evaluator
alias Pulse.PromQL.QuerySlots
alias Pulse.PromQL.TaskSupervisor
alias Pulse.Record.MetricSample
alias Pulse.Runtime
alias Pulse.Storage.Memory

promtool = List.first(System.argv()) || System.find_executable("promtool") || raise "promtool is required"
{version, status} = System.cmd(promtool, ["--version"], stderr_to_stdout: true)

if status != 0 or not String.contains?(version, "version 3.5.0 ("),
  do: raise("the checked-in oracle requires promtool 3.5.0")

fixture = Path.expand("../test/fixtures/promql/conformance.json", __DIR__) |> File.read!() |> JSON.decode!()

Runtime.install(
  Runtime.new(
    instance: Conformance,
    configs: Map.new(Application.get_all_env(:pulse), fn {key, value} -> {{:pulse, key}, value} end)
  )
)

Runtime.put_env(:pulse, Pulse.Storage, adapter: Memory)

children = [
  Memory,
  Pulse.Metrics,
  Pulse.SelfMetrics,
  {Task.Supervisor, name: TaskSupervisor, max_children: 4},
  {Registry, keys: :unique, name: QuerySlots}
]

{:ok, supervisor} = Supervisor.start_link(Enum.map(children, &Runtime.child_spec/1), strategy: :one_for_one)
Memory.reset()
interval = fixture["interval_seconds"]

decode_value = fn
  "stale" -> :stale
  "NaN" -> :nan
  "Inf" -> :infinity
  "-Inf" -> :negative_infinity
  value when is_number(value) -> value * 1.0
end

for series <- fixture["series"] do
  samples =
    series["values"]
    |> Enum.with_index()
    |> Enum.reject(fn {value, _} -> value == "_" end)
    |> Enum.map(fn {value, index} ->
      %MetricSample{
        labels: series["labels"],
        value: decode_value.(value),
        timestamp_ns: index * interval * 1_000_000_000
      }
    end)

  :ok = Memory.append(:metrics, "oracle", samples)
end

labels = fn labels ->
  "{" <> (labels |> Enum.sort() |> Enum.map_join(",", fn {key, value} -> key <> "=" <> JSON.encode!(value) end)) <> "}"
end

# YAML scalars for IEEE values cannot be represented by JSON numeric literals.
value_yaml = fn
  "NaN" -> ".nan"
  "+Inf" -> ".inf"
  "-Inf" -> "-.inf"
  value -> value
end

inputs =
  Enum.map_join(fixture["series"], "\n", fn series ->
    values = Enum.map_join(series["values"], " ", &to_string/1)
    "    - series: #{JSON.encode!(labels.(series["labels"]))}\n      values: #{JSON.encode!(values)}"
  end)

results =
  for test <- fixture["queries"], seconds <- test["times"] do
    expr = test["expr"]

    result =
      case Evaluator.query(expr, "oracle", %{end_ts_ns: seconds * 1_000_000_000}) do
        {:ok, result} -> result["data"]
        error -> raise "#{expr} at #{seconds}s: #{inspect(error)}"
      end

    %{"expr" => expr, "seconds" => seconds, "data" => result}
  end

cases =
  for test <- results do
    expr = test["expr"]
    seconds = test["seconds"]
    result = test["data"]

    samples =
      case result["resultType"] do
        "vector" -> Enum.map(result["result"], fn sample -> {sample["metric"], Enum.at(sample["value"], 1)} end)
        "scalar" -> [{%{}, Enum.at(result["result"], 1)}]
      end

    # promtool 3.5 compares YAML NaN by bit pattern. Prove its positions
    # independently with a bool mask, then verify the non-NaN values normally.
    has_nan = Enum.any?(samples, fn {_, value} -> value == "NaN" end)

    nan_mask =
      if has_nan do
        "    - expr: #{JSON.encode!("(#{expr}) != bool (#{expr})")}\n      eval_time: #{seconds}s\n      exp_samples:\n" <>
          Enum.map_join(samples, "\n", fn {metric, value} ->
            metric = Map.delete(metric, "__name__")

            "        - labels: #{JSON.encode!(labels.(metric))}\n          value: #{if value == "NaN", do: "1", else: "0"}"
          end) <> "\n"
      else
        ""
      end

    expr = if has_nan, do: "(#{expr}) == (#{expr})", else: expr
    samples = Enum.reject(samples, fn {_, value} -> value == "NaN" end)

    expected =
      if samples == [],
        do: "      exp_samples: []",
        else:
          "      exp_samples:\n" <>
            Enum.map_join(samples, "\n", fn {metric, value} ->
              "        - labels: #{JSON.encode!(labels.(metric))}\n          value: #{value_yaml.(value)}"
            end)

    nan_mask <> "    - expr: #{JSON.encode!(expr)}\n      eval_time: #{seconds}s\n" <> expected
  end

# Fuzzy comparison accepts adjacent encodings across zero/subnormal and
# maximum-finite/infinity boundaries. Independently verify classifications
# as exact 0/1 predicates, including the sign of every zero result.
classification_cases =
  for test <- results,
      test["expr"] in Enum.map(~w(ceil sqrt exp ln log2 log10), &"#{&1}(math_input)"),
      {predicate, classify} <- [
        {"(#{test["expr"]}) != bool (#{test["expr"]})", &(&1 == "NaN")},
        {"(#{test["expr"]}) == bool 0", &(&1 in ["0", "-0"])},
        {"(#{test["expr"]}) == bool Inf", &(&1 == "+Inf")},
        {"(#{test["expr"]}) == bool -Inf", &(&1 == "-Inf")},
        {"((#{test["expr"]}) == bool 0) * ((1 / (#{test["expr"]})) == bool -Inf)", &(&1 == "-0")}
      ] do
    samples = test["data"]["result"]

    expected =
      if samples == [],
        do: "      exp_samples: []",
        else:
          "      exp_samples:\n" <>
            Enum.map_join(samples, "\n", fn sample ->
              value = if classify.(Enum.at(sample["value"], 1)), do: 1, else: 0
              "        - labels: #{JSON.encode!(labels.(sample["metric"]))}\n          value: #{value}"
            end)

    "    - expr: #{JSON.encode!(predicate)}\n      eval_time: #{test["seconds"]}s\n" <> expected
  end

yaml =
  "rule_files: []\nfuzzy_compare: true\nevaluation_interval: #{interval}s\ntests:\n  - interval: #{interval}s\n    input_series:\n" <>
    inputs <> "\n    promql_expr_test:\n" <> Enum.join(cases, "\n") <> "\n"

path = Path.join(System.tmp_dir!(), "pulse-promql-#{Base.encode16(:crypto.strong_rand_bytes(8))}.yaml")

try do
  File.write!(path, yaml)
  {output, status} = System.cmd(promtool, ["test", "rules", path], stderr_to_stdout: true)
  IO.write(output)

  if status != 0 do
    artifact = System.get_env("PULSE_CONFORMANCE_ARTIFACT")
    if artifact, do: File.write!(artifact, yaml)
    raise "promtool found numerical/label mismatches (#{length(cases)} cases)"
  end

  classification_yaml =
    "rule_files: []\nevaluation_interval: #{interval}s\ntests:\n  - interval: #{interval}s\n    input_series:\n" <>
      inputs <> "\n    promql_expr_test:\n" <> Enum.join(classification_cases, "\n") <> "\n"

  File.write!(path, classification_yaml)
  {classification_output, classification_status} = System.cmd(promtool, ["test", "rules", path], stderr_to_stdout: true)
  IO.write(classification_output)

  if classification_status != 0 do
    artifact = System.get_env("PULSE_CONFORMANCE_ARTIFACT")
    if artifact, do: File.write!(artifact, classification_yaml)
    raise "promtool found an exact math classification mismatch"
  end

  # A huge test interval keeps this exact large-epoch check to two ticks.
  # No fuzzy comparison: timestamp rounding can affect equality and alerts.
  epoch_ms = 1_700_000_000_123

  :ok =
    Memory.append(:metrics, "epoch", [
      %MetricSample{labels: %{"__name__" => "epoch"}, value: 1.0, timestamp_ns: epoch_ms * 1_000_000}
    ])

  epoch_tests =
    Enum.map_join(
      ["timestamp(epoch)", "time()", "timestamp(epoch) == 1700000000.123", "sgn(timestamp(epoch) - 1700000000.123)"],
      "\n",
      fn expr ->
        {:ok, %{"data" => data}} = Evaluator.query(expr, "epoch", %{end_ts_ns: epoch_ms * 1_000_000})
        sample = if data["resultType"] == "scalar", do: data["result"], else: hd(data["result"])["value"]

        "    - expr: #{JSON.encode!(expr)}\n      eval_time: #{epoch_ms}ms\n      exp_samples:\n        - labels: '{}'\n          value: #{Enum.at(sample, 1)}"
      end
    )

  epoch_yaml =
    "rule_files: []\nevaluation_interval: #{epoch_ms}ms\ntests:\n  - interval: #{epoch_ms}ms\n    input_series:\n    - series: 'epoch'\n      values: '0 1'\n    promql_expr_test:\n" <>
      epoch_tests <> "\n"

  File.write!(path, epoch_yaml)
  {epoch_output, epoch_status} = System.cmd(promtool, ["test", "rules", path], stderr_to_stdout: true)
  IO.write(epoch_output)
  if epoch_status != 0, do: raise("promtool found an exact epoch-timestamp mismatch")

  if destination = System.get_env("PULSE_CONFORMANCE_RESULTS") do
    File.write!(
      destination,
      JSON.encode!(%{
        "fixture_sha256" =>
          Base.encode16(
            :crypto.hash(:sha256, File.read!(Path.expand("../test/fixtures/promql/conformance.json", __DIR__))),
            case: :lower
          ),
        "oracle" => "Prometheus promtool 3.5.0",
        "cases" => results
      })
    )
  end

  IO.puts(
    "Independent Prometheus conformance: #{length(cases)} cases, " <>
      "#{length(classification_cases)} exact math classifications and 4 exact epoch checks passed"
  )
after
  File.rm(path)
  Supervisor.stop(supervisor)
end
