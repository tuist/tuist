defmodule Pulse.Reliability.Windows do
  @moduledoc """
  Bounded, descriptive service/environment evidence, not a health detector.

  Windows are half-open: thirty baseline minutes followed by five current
  minutes. Bins use the finish time's minute phase; changing that phase forces
  a full rescan to preserve exact boundaries. Otherwise the last ten minutes
  of the previous capture plus elapsed time are replaced, never added twice.
  Previously known groups remain visible, even with no observations.

  Each signal gets one joint read and its own hard storage budgets. Thus an
  attempt admits at most 30,000 returned rows, 8 MiB decoded log buffers,
  384 segments, 48 MiB scanned bytes and 300,000 scanned rows (the decoded
  byte option is currently enforced only for logs). All reads share an absolute
  monotonic millisecond deadline. Snapshot JSON is capped at 4 MiB.

  Metrics are scalar sample inventories, not rates or instrument semantics;
  labels other than identity/name are discarded. Inventories select at most
  eight names per group across both windows; exclusion counts include samples
  lost to minute-local selection. Selected statistics are not complete series
  when exclusions exist. Trace statistics describe
  observed server spans only, not total request traffic. Log evidence contains
  bounded shape signatures, never message text. No query performs raw reads.
  Storage errors, including S3 `:not_found` for missing published segments,
  fail the whole capture rather than imply health. An explicitly distinguished
  missing signal authority is absent observations, never a healthy signal.
  Callers must supply an unmodified, same-tenant previous snapshot.
  """

  alias Pulse.Record.{Log, MetricSample, Span}
  alias Pulse.Storage

  @minute 60_000_000_000
  @max_time 9_223_372_036_854_775_807
  @cap 4 * 1024 * 1024
  @queries ~w(log_patterns slow_traces metric_inventory)
  @services ~w(service_name service.name service job)
  @environments ~w(deployment_environment deployment.environment.name deployment_environment_name deployment.environment environment env)

  def scan(tenant, previous, finish_ns, deadline_ms)
      when is_binary(tenant) and is_integer(finish_ns) and finish_ns >= 35 * @minute and finish_ns <= @max_time and
             is_integer(deadline_ms) do
    check_deadline(deadline_ms)
    {old_groups, old_bins, repair} = prior(previous, finish_ns)
    start = finish_ns - 35 * @minute
    bins = Map.filter(old_bins, fn {key, _} -> String.to_integer(key) >= start and String.to_integer(key) < repair end)

    opts = [
      start_ts: repair,
      end_ts: finish_ns - 1,
      fresh: true,
      distinguish_missing_authority: true,
      max_records: 10_000,
      max_decoded_bytes: 8 * 1024 * 1024,
      max_scan_segments: 128,
      max_scan_bytes: 16 * 1024 * 1024,
      max_scan_rows: 100_000,
      deadline_ms: deadline_ms
    ]

    {bins, identities} = read_signals(tenant, opts, {bins, old_groups})
    bins = cap_inventory(bins, identities)
    groups = summarize_groups(bins, identities, start, finish_ns)

    snapshot = %{
      "version" => 1,
      "finish_ns" => finish_ns,
      "groups" => groups,
      "bins" => bins,
      "coverage" => %{
        "start_ns" => start,
        "repair_start_ns" => repair,
        "state" => "observations_only",
        "late_arrivals_before_repair" => "not_rechecked",
        "trace_population" => "observed_sampled_server_spans",
        "empty_windows" => "missing_not_healthy"
      },
      "exclusions" => [
        "non_scalar_or_nonfinite_metrics",
        "metric_names_beyond_8",
        "non_server_spans",
        "log_shapes_beyond_4"
      ]
    }

    require!(byte_size(Pulse.JSON.encode!(snapshot)) <= @cap, :reliability_snapshot_limit)
    check_deadline(deadline_ms)
    {:ok, snapshot}
  catch
    {:windows_error, reason} -> {:error, reason}
  end

  def scan(_, _, _, _), do: {:error, :reliability_invalid_window}

  def input(group) do
    Enum.reduce(~w(baseline current), Map.take(group, ~w(id service environment)), fn window, input ->
      summary = group[window]

      compact =
        summary
        |> update_in(["logs"], &Map.delete(&1, "patterns"))
        |> update_in(["metrics"], &Map.delete(&1, "names"))
        |> update_in(["traces"], &Map.drop(&1, ~w(histogram histogram_upper_exclusive_ns)))

      Map.put(input, window, compact)
    end)
  end

  def query(group, id) when id in @queries, do: Map.fetch(group["queries"], id)
  def query(_, _), do: {:error, :unknown_query}

  defp read_signals(tenant, opts, acc) do
    Enum.reduce([:logs, :metrics, :traces], acc, fn signal, acc ->
      check_deadline(opts[:deadline_ms])
      reduce_read(Storage.query(signal, tenant, opts), signal, acc, opts)
    end)
  end

  defp reduce_read({:ok, rows}, signal, acc, opts) when is_list(rows) do
    require!(length(rows) <= 10_000, :reliability_row_limit)
    Enum.reduce(rows, acc, &add(&1, signal, &2, opts[:start_ts], opts[:end_ts] + 1))
  end

  defp reduce_read({:error, :signal_authority_missing}, _signal, acc, _opts), do: acc
  defp reduce_read({:error, reason}, _signal, _acc, _opts), do: throw({:windows_error, reason})
  defp reduce_read(_, _signal, _acc, _opts), do: throw({:windows_error, :reliability_invalid_rows})

  defp summarize_groups(bins, identities, start, finish) do
    Map.new(identities, fn {id, identity} ->
      baseline = summarize(bins, id, start, finish - 5 * @minute)
      current = summarize(bins, id, finish - 5 * @minute, finish)

      queries = %{
        "log_patterns" => evidence(baseline, current, "logs"),
        "slow_traces" => evidence(baseline, current, "traces"),
        "metric_inventory" => evidence(baseline, current, "metrics")
      }

      {id, Map.merge(identity, %{"baseline" => baseline, "current" => current, "queries" => queries})}
    end)
  end

  defp prior(nil, finish), do: {%{}, %{}, finish - 35 * @minute}

  defp prior(%{"version" => 1, "finish_ns" => before, "groups" => groups, "bins" => bins}, finish)
       when is_integer(before) and before <= finish and is_map(groups) and is_map(bins) do
    require!(map_size(groups) <= 100, :reliability_group_limit)
    identities = Map.new(groups, fn {id, group} -> {id, Map.take(group, ~w(id service environment))} end)

    if rem(before, @minute) == rem(finish, @minute) do
      {identities, bins, max(finish - 35 * @minute, before - 10 * @minute)}
    else
      {identities, %{}, finish - 35 * @minute}
    end
  end

  defp prior(_, _), do: throw({:windows_error, :reliability_invalid_previous})

  defp add(row, signal, {bins, identities}, start, finish) do
    validate(row, signal)
    ts = row.timestamp_ns
    require!(is_integer(ts) and ts >= start and ts < finish and ts <= @max_time, :reliability_invalid_time)
    {service, environment} = identity(row)
    id = digest(Pulse.JSON.encode!([service, environment]))
    identity = %{"id" => id, "service" => service, "environment" => environment}
    identities = Map.put(identities, id, identity)
    require!(map_size(identities) <= 100, :reliability_group_limit)
    key = Integer.to_string(finish - (div(finish - 1 - ts, @minute) + 1) * @minute)
    minute = Map.get(bins, key, %{})
    summary = reduce_row(Map.get(minute, id, empty()), row)
    {Map.put(bins, key, Map.put(minute, id, summary)), identities}
  end

  defp validate(
         %Log{resource: resource, severity_number: n, severity_text: text, observed_timestamp_ns: observed},
         :logs
       ) do
    require!(is_map(resource), :reliability_invalid_row)
    require!(is_nil(n) or (is_integer(n) and n in 0..24), :reliability_invalid_row)
    require!(is_nil(text) or is_binary(text), :reliability_invalid_row)
    require!(optional_timestamp?(observed), :reliability_invalid_time)
  end

  defp validate(%MetricSample{labels: labels}, :metrics), do: require!(is_map(labels), :reliability_invalid_row)

  defp validate(%Span{} = row, :traces) do
    require!(
      is_map(row.resource) and row.kind in 0..5 and is_map(row.status) and
        row.status["code"] in 0..2,
      :reliability_invalid_row
    )

    require!(
      is_integer(row.end_timestamp_ns) and is_integer(row.timestamp_ns) and
        row.end_timestamp_ns >= row.timestamp_ns and row.end_timestamp_ns <= @max_time,
      :reliability_invalid_time
    )
  end

  defp validate(_, _), do: throw({:windows_error, :reliability_invalid_row})

  defp optional_timestamp?(nil), do: true
  defp optional_timestamp?(ts), do: is_integer(ts) and ts >= 0 and ts <= @max_time

  # Logs/metrics retain resource metadata; traces retain the attribute list
  # directly. Typed resources are authoritative: projections can stringify
  # bytes/nonfinite values or turn service.name into a namespaced metric job.
  defp identity(%{otlp: %{"resource" => %{"attributes" => attributes}}}), do: resource_identity(attributes)
  defp identity(%{otlp: %{"resource" => attributes}}) when is_list(attributes), do: resource_identity(attributes)

  defp identity(%MetricSample{labels: labels}), do: {dimension(labels, @services), dimension(labels, @environments)}

  defp identity(row) do
    service = if row.service in [nil, ""], do: dimension(row.resource, @services), else: text(row.service)
    {service, dimension(row.resource, @environments)}
  end

  defp resource_identity(attributes) do
    values =
      Map.new(
        for %{"key" => key, "value" => value} <- attributes,
            key in ~w(service.name deployment.environment.name deployment.environment),
            do: {key, value}
      )

    # Only the deprecated semantic key is a fallback, and only when the new
    # environment key is absent. Present nonstring/empty values stay unknown.
    environment = Map.get(values, "deployment.environment.name", values["deployment.environment"])
    {resource_dimension(values["service.name"]), resource_dimension(environment)}
  end

  defp resource_dimension(%{"stringValue" => value}) when is_binary(value) and value != "", do: text(value)
  defp resource_dimension(_), do: "unknown"

  defp dimension(map, keys) do
    value = Enum.find_value(keys, &dimension_value(map, &1))
    text(value || "unknown")
  end

  defp dimension_value(map, key), do: if(map[key] not in [nil, ""], do: map[key])

  defp text(value) do
    require!(is_binary(value) and byte_size(value) <= 128 and String.valid?(value), :reliability_identity_limit)
    :binary.copy(value)
  end

  defp empty do
    %{
      "logs" => %{"count" => 0, "errors" => 0, "patterns" => %{}, "excluded_patterns" => 0},
      "metrics" => %{"count" => 0, "names" => %{}, "excluded_samples" => 0},
      "traces" => %{
        "count" => 0,
        "errors" => 0,
        "excluded_spans" => 0,
        "duration_ns" => nil,
        "histogram" => List.duplicate(0, 6)
      }
    }
  end

  defp error_text?(text) when is_binary(text) and byte_size(text) <= 32,
    do: String.upcase(text) in ~w(ERROR FATAL CRITICAL)

  defp error_text?(_), do: false

  defp reduce_row(summary, %Log{} = row) do
    error =
      (is_integer(row.severity_number) and row.severity_number >= 17) or
        error_text?(row.severity_text)

    # Shape hashing discards all original tokens, including secrets. Bound work
    # independently of the body size and never retain a body sub-binary.
    shape = if is_binary(row.body), do: binary_part(row.body, 0, min(byte_size(row.body), 1024)), else: ""

    signature =
      shape
      |> :binary.bin_to_list()
      |> Enum.map(fn c ->
        cond do
          c in ?0..?9 -> ?0
          c in [?\s, ?\t, ?\n, ?\r] -> ?\s
          true -> ?x
        end
      end)
      |> :erlang.list_to_binary()
      |> digest()

    update_in(summary["logs"], fn logs ->
      {patterns, excluded} = bounded_counts(logs["patterns"], signature, 1, 4)

      %{
        logs
        | "count" => logs["count"] + 1,
          "errors" => logs["errors"] + if(error, do: 1, else: 0),
          "patterns" => patterns,
          "excluded_patterns" => logs["excluded_patterns"] + excluded
      }
    end)
  end

  defp reduce_row(summary, %MetricSample{} = row) do
    name = row.labels["__name__"]
    value = row.value

    valid =
      is_binary(name) and name != "" and byte_size(name) <= 128 and String.valid?(name) and
        is_nil(row.histogram) and finite?(value)

    update_in(summary["metrics"], fn metrics ->
      names = metrics["names"]

      if valid and (Map.has_key?(names, name) or map_size(names) < 8) do
        stats = stats_merge(names[name], stats(value, row.timestamp_ns))
        %{metrics | "count" => metrics["count"] + 1, "names" => Map.put(names, :binary.copy(name), stats)}
      else
        %{metrics | "count" => metrics["count"] + 1, "excluded_samples" => metrics["excluded_samples"] + 1}
      end
    end)
  end

  defp reduce_row(summary, %Span{kind: kind}) when kind != 2,
    do: update_in(summary["traces"]["excluded_spans"], &(&1 + 1))

  defp reduce_row(summary, %Span{} = row) do
    duration = row.end_timestamp_ns - row.timestamp_ns
    bucket = Enum.count([1_000_000, 10_000_000, 100_000_000, 1_000_000_000, 10_000_000_000], &(duration >= &1))

    update_in(summary["traces"], fn traces ->
      %{
        traces
        | "count" => traces["count"] + 1,
          "errors" => traces["errors"] + if(row.status["code"] == 2, do: 1, else: 0),
          "duration_ns" => stats_merge(traces["duration_ns"], stats(duration, row.timestamp_ns)),
          "histogram" => List.update_at(traces["histogram"], bucket, &(&1 + 1))
      }
    end)
  end

  defp finite?(n) when is_integer(n), do: abs(n) <= 1.797_693_134_862_315_7e308
  defp finite?(n) when is_float(n), do: true
  defp finite?(_), do: false

  defp stats(value, ts), do: %{"count" => 1, "min" => value, "max" => value, "last" => value, "last_ns" => ts}
  defp stats_merge(nil, right), do: right
  defp stats_merge(left, nil), do: left

  defp stats_merge(left, right) do
    latest = if {left["last_ns"], left["last"]} >= {right["last_ns"], right["last"]}, do: left, else: right

    %{
      latest
      | "count" => left["count"] + right["count"],
        "min" => min(left["min"], right["min"]),
        "max" => max(left["max"], right["max"])
    }
  end

  defp cap_inventory(bins, identities) do
    allowed = Map.new(identities, fn {id, _} -> {id, inventory_names(bins, id)} end)

    Map.new(bins, fn {key, groups} ->
      {key, Map.new(groups, fn {id, summary} -> {id, select_inventory(summary, allowed[id])} end)}
    end)
  end

  defp inventory_names(bins, id) do
    bins
    |> Enum.flat_map(fn {_, groups} -> bin_inventory_names(groups[id]) end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.take(8)
  end

  defp bin_inventory_names(nil), do: []
  defp bin_inventory_names(summary), do: Map.keys(summary["metrics"]["names"])

  defp select_inventory(summary, allowed) do
    metrics = summary["metrics"]
    {kept, dropped} = Map.split(metrics["names"], allowed)
    excluded = Enum.reduce(dropped, metrics["excluded_samples"], fn {_, stats}, n -> n + stats["count"] end)
    %{summary | "metrics" => %{metrics | "names" => kept, "excluded_samples" => excluded}}
  end

  defp summarize(bins, id, start, finish) do
    bins
    |> Enum.filter(fn {key, _} -> String.to_integer(key) >= start and String.to_integer(key) < finish end)
    |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
    |> Enum.reduce(empty(), fn {_, groups}, acc -> merge(acc, Map.get(groups, id, empty())) end)
    |> Map.put("start_ns", start)
    |> Map.put("finish_ns", finish)
    |> Map.put("coverage", "observations_only_missing_is_unknown")
    |> Map.put("caveats", [
      "sampled_server_spans_not_request_traffic",
      "metric_samples_not_rates_or_complete_series",
      "log_shape_signatures_not_message_templates",
      "late_arrivals_may_be_missing"
    ])
    |> update_in(
      ["traces"],
      &Map.put(&1, "histogram_upper_exclusive_ns", [
        1_000_000,
        10_000_000,
        100_000_000,
        1_000_000_000,
        10_000_000_000,
        "+Inf"
      ])
    )
  end

  defp merge(left, right) do
    Map.new(left, fn {signal, a} ->
      b = right[signal]
      combined = Map.new(a, &merge_field(&1, b))
      {signal, merge_inventory(signal, combined, a, b)}
    end)
  end

  defp merge_field({"duration_ns", value}, right), do: {"duration_ns", stats_merge(value, right["duration_ns"])}
  defp merge_field({"histogram", value}, right), do: {"histogram", Enum.zip_with(value, right["histogram"], &+/2)}
  defp merge_field({key, value}, _right) when key in ["names", "patterns"], do: {key, value}
  defp merge_field({key, value}, right), do: {key, value + right[key]}

  defp merge_inventory("logs", combined, left, right) do
    {patterns, excluded} = Enum.reduce(Enum.sort(right["patterns"]), {left["patterns"], 0}, &merge_pattern/2)
    %{combined | "patterns" => patterns, "excluded_patterns" => combined["excluded_patterns"] + excluded}
  end

  defp merge_inventory("metrics", combined, left, right) do
    {names, excluded} = Enum.reduce(Enum.sort(right["names"]), {left["names"], 0}, &merge_metric/2)
    %{combined | "names" => names, "excluded_samples" => combined["excluded_samples"] + excluded}
  end

  defp merge_inventory("traces", combined, _left, _right), do: combined

  defp merge_pattern({key, count}, {map, excluded}) do
    {map, extra} = bounded_counts(map, key, count, 4)
    {map, excluded + extra}
  end

  defp merge_metric({key, value}, {map, excluded}) do
    if Map.has_key?(map, key) or map_size(map) < 8,
      do: {Map.put(map, key, stats_merge(map[key], value)), excluded},
      else: {map, excluded + value["count"]}
  end

  defp bounded_counts(map, key, count, cap) do
    if Map.has_key?(map, key) or map_size(map) < cap,
      do: {Map.update(map, key, count, &(&1 + count)), 0},
      else: {map, count}
  end

  defp evidence(baseline, current, key), do: %{"baseline" => baseline[key], "current" => current[key]}
  defp digest(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  defp check_deadline(deadline), do: require!(System.monotonic_time(:millisecond) < deadline, :query_timeout)
  defp require!(true, _), do: :ok
  defp require!(_, reason), do: throw({:windows_error, reason})
end
