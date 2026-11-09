defmodule Pulse.Storage.S3.Manifest.Segment do
  @moduledoc """
  One row inside a manifest — the identity and summary metadata of a
  segment that has been PUT to S3.

  `key` is the FULL S3 object key (`tenants/<tenant>/v3/logs/<tail>`),
  not the tail alone. The wire form uses only the tail, and
  `from_wire/1` requires the containing tenant + signal to reconstitute
  the full key. Keeping the full key in memory means the query path can
  hand it straight to `ObjectStore.get/2` without a per-segment format
  operation.
  """

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.Storage.S3.MetricLabelSummary
  alias Pulse.Storage.S3.TraceSummary

  defstruct [
    :key,
    :min_ts,
    :max_ts,
    :row_count,
    :byte_size,
    :metric_names,
    :metric_name_bloom,
    :log_services,
    :metric_labels,
    :trace_summary,
    :log_labels,
    :log_minutes,
    :catalog
  ]

  @type t :: %__MODULE__{
          key: String.t(),
          min_ts: non_neg_integer() | nil,
          max_ts: non_neg_integer() | nil,
          row_count: non_neg_integer() | nil,
          byte_size: non_neg_integer() | nil,
          metric_names: [String.t()] | nil,
          metric_name_bloom: binary() | nil,
          log_services: [String.t()] | nil,
          metric_labels: %{String.t() => [String.t()]} | nil,
          trace_summary: TraceSummary.t() | nil,
          log_labels: %{String.t() => [String.t()]} | nil,
          log_minutes: %{integer() => pos_integer()} | nil,
          catalog: String.t() | nil
        }

  @doc """
  Build a segment record for a segment the ingester just wrote.

  `tail` is the object key with the leading `tenants/<tenant>/v3/<signal>/`
  stripped. The struct holds the full key so the query path never has to
  re-glue the prefix.
  """
  @spec build(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def build(key, min_ts, max_ts, row_count)
      when is_binary(key) and is_integer(min_ts) and is_integer(max_ts) and is_integer(row_count) do
    %__MODULE__{
      key: key,
      min_ts: min_ts,
      max_ts: max_ts,
      row_count: row_count,
      byte_size: nil
    }
  end

  @spec build(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer() | nil
        ) :: t()
  def build(key, min_ts, max_ts, row_count, byte_size)
      when is_binary(key) and is_integer(min_ts) and is_integer(max_ts) and is_integer(row_count) do
    %__MODULE__{
      key: key,
      min_ts: min_ts,
      max_ts: max_ts,
      row_count: row_count,
      byte_size: byte_size
    }
  end

  @doc """
  Reduce a segment to its compact wire form: short keys, the segment's
  key relative to its containing tenant/signal prefix.
  """
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = segment) do
    base = %{
      "k" => segment.key,
      "mn" => segment.min_ts,
      "mx" => segment.max_ts,
      "r" => segment.row_count
    }

    base =
      Enum.reduce(
        [
          {"b", segment.byte_size},
          {"n", segment.metric_names},
          {"ls", segment.log_services},
          {"l", segment.metric_labels},
          {"el", segment.log_labels},
          {"cg", segment.catalog}
        ],
        base,
        fn
          {_key, value}, acc when value in [nil, false] -> acc
          {key, value}, acc -> Map.put(acc, key, value)
        end
      )

    base = if segment.metric_name_bloom, do: Map.put(base, "nb", Base.encode64(segment.metric_name_bloom)), else: base
    base = if segment.log_minutes, do: Map.put(base, "lm", minutes_to_wire(segment.log_minutes)), else: base
    if segment.trace_summary, do: Map.put(base, "t", TraceSummary.to_wire(segment.trace_summary)), else: base
  end

  @doc """
  Parse one wire-form segment. Returns `{:error, :invalid_segment}` on
  a shape that the writer would never produce, so a garbled manifest
  fails loudly rather than silently mispruning a query.
  """
  @spec from_wire(map()) :: {:ok, t()} | {:error, :invalid_segment}
  def from_wire(%{"k" => key, "mn" => min_ts, "mx" => max_ts} = wire)
      when is_binary(key) and is_integer(min_ts) and is_integer(max_ts) do
    row_count = valid_non_neg(wire["r"])
    byte_size = valid_non_neg(wire["b"])

    {:ok,
     %__MODULE__{
       key: key,
       min_ts: min_ts,
       max_ts: max_ts,
       row_count: row_count,
       byte_size: byte_size,
       metric_names: valid_names(wire["n"]),
       metric_name_bloom: valid_name_bloom(wire["nb"]),
       log_services: valid_services(wire["ls"]),
       metric_labels: MetricLabelSummary.parse(wire["l"]),
       trace_summary: TraceSummary.parse(wire["t"]),
       log_labels: MetricLabelSummary.parse(wire["el"]),
       log_minutes: valid_minutes(wire["lm"]),
       catalog: valid_lineage(wire["cg"])
     }}
  end

  def from_wire(_), do: {:error, :invalid_segment}

  # ---- per-minute log line counts --------------------------------------------

  @minute_ns 60_000_000_000
  @max_minutes 128

  @doc """
  The minute bucket of a log timestamp: the bucket numbered `m` holds the
  lines with `(m - 1) * 60s < ts <= m * 60s`, the window shape of a LogQL
  range ending on a minute (`native/pulse_codec/src/log_rollup.rs`).
  """
  def log_minute(ts) when is_integer(ts), do: Integer.floor_div(ts - 1, @minute_ns) + 1
  def minute_ns, do: @minute_ns

  @doc """
  Exact line counts per minute bucket of `timestamps`, or nil above
  #{@max_minutes} buckets. Log rollups (`Pulse.Storage.S3.LogRollups`) are
  valid for a minute only while these counts sum to theirs.
  """
  def log_minutes(timestamps) do
    counts = Enum.frequencies_by(timestamps, &log_minute/1)
    if map_size(counts) <= @max_minutes, do: counts
  end

  @doc "Line counts of a segment holding exactly the rows of segments with `minutes`."
  def merge_log_minutes(minutes) do
    if !Enum.any?(minutes, &is_nil/1) do
      merged = Enum.reduce(minutes, %{}, &Map.merge(&2, &1, fn _minute, a, b -> a + b end))
      if map_size(merged) <= @max_minutes * 2, do: merged
    end
  end

  defp minutes_to_wire(minutes), do: minutes |> Enum.sort() |> Enum.map(fn {m, c} -> [m, c] end)

  defp valid_minutes(pairs) when is_list(pairs) and length(pairs) <= @max_minutes * 2 do
    Enum.reduce_while(pairs, %{}, fn
      [m, c], acc when is_integer(m) and is_integer(c) and c > 0 -> {:cont, Map.put(acc, m, c)}
      _, _ -> {:halt, nil}
    end)
  end

  defp valid_minutes(_), do: nil

  @doc """
  Does this segment's `[min_ts, max_ts]` intersect `[start_ts, end_ts]`?
  A nil bound on either side is treated as unbounded on that side.
  Segments whose own bounds are nil are kept — the query cannot safely
  skip them without knowing their real range.
  """
  @spec intersects?(t(), non_neg_integer() | nil, non_neg_integer() | nil) :: boolean()
  def intersects?(%__MODULE__{min_ts: nil}, _start_ts, _end_ts), do: true
  def intersects?(%__MODULE__{max_ts: nil}, _start_ts, _end_ts), do: true

  def intersects?(%__MODULE__{min_ts: min_ts, max_ts: max_ts}, start_ts, end_ts) do
    (start_ts == nil or max_ts >= start_ts) and (end_ts == nil or min_ts <= end_ts)
  end

  # Unknown or malformed summaries must never exclude a segment.
  defp valid_names(names) when is_list(names) do
    if length(names) <= 128 and Enum.all?(names, &(is_binary(&1) and byte_size(&1) <= 256)),
      do: names
  end

  defp valid_names(_), do: nil

  # A remote-write batch commonly carries hundreds of metric names. Up to 128
  # names are listed exactly; up to 2,048 are summarized by a bloom filter of
  # 16 bits per name (under 0.1% false positives), capped at 1 KiB (still at
  # least four bits per name), much smaller than the list it replaces. More
  # names, or names that are too long or not UTF-8, leave the set unknown.
  @listed_names 128
  @bloom_names 2048
  @bloom_sizes [64, 128, 256, 512, 1024]

  @doc "Attach a complete, bounded metric-name set; nil means unknown, never truncated."
  def summarize_metrics(segment, records) do
    names = Enum.reduce_while(records, MapSet.new(), &collect_metric_name/2)

    {listed, bloom} =
      cond do
        names == nil -> {nil, nil}
        MapSet.size(names) <= @listed_names -> {names |> Enum.map(&:binary.copy/1) |> Enum.sort(), nil}
        true -> {nil, name_bloom(names)}
      end

    %{segment | metric_names: listed, metric_name_bloom: bloom, metric_labels: MetricLabelSummary.build(records)}
  end

  defp collect_metric_name(record, names) do
    name = Map.get(record.labels, "__name__", "")

    if is_binary(name) and byte_size(name) <= 256 and String.valid?(name) do
      names = MapSet.put(names, name)
      if MapSet.size(names) <= @bloom_names, do: {:cont, names}, else: {:halt, nil}
    else
      {:halt, nil}
    end
  end

  defp name_bloom(names) do
    wanted = MapSet.size(names) * 2
    bytes = Enum.find(@bloom_sizes, List.last(@bloom_sizes), &(&1 >= wanted))
    size = bytes * 8

    bits =
      Enum.reduce(names, 0, fn name, bits ->
        Enum.reduce(bloom_positions(name_hash(name), size), bits, &bor(&2, bsl(1, &1)))
      end)

    <<bits::unsigned-size(size)>>
  end

  defp name_hash(name) do
    <<hash::64, _::binary>> = :crypto.hash(:sha256, name)
    hash
  end

  defp bloom_positions(hash, size) do
    a = bsr(hash, 32)
    b = bor(band(hash, 0xFFFFFFFF), 1)
    Enum.map(0..3, &rem(a + &1 * b, size))
  end

  # Bit `p` of the big-endian integer the bloom was built from.
  defp bloom_member?(bits, hash) do
    last = byte_size(bits) - 1

    Enum.all?(bloom_positions(hash, byte_size(bits) * 8), fn p ->
      band(:binary.at(bits, last - div(p, 8)), bsl(1, rem(p, 8))) != 0
    end)
  end

  defp valid_name_bloom(encoded) when is_binary(encoded) and byte_size(encoded) <= 1368 do
    with {:ok, bits} <- Base.decode64(encoded),
         true <- byte_size(bits) in @bloom_sizes,
         true <- bits != :binary.copy(<<0>>, byte_size(bits)) do
      :binary.copy(bits)
    else
      _ -> nil
    end
  end

  defp valid_name_bloom(_), do: nil

  defp valid_lineage(lineage) when is_binary(lineage) and byte_size(lineage) in 1..64, do: lineage
  defp valid_lineage(_), do: nil

  @doc "Keep unknown summaries and segments whose name set could satisfy every name matcher."
  def matches_metric_name?(segment, matchers) do
    matchers = Enum.filter(matchers, &match?({"__name__", _, _}, &1))
    matches_metrics?(segment, metrics_filter(matchers))
  end

  @doc """
  Storage tier of a metric segment, from its key: `:rollup` for hourly
  rollup objects, `:final` for segments of a finalized hour, `:grouped` for
  name-grouped consolidations of part of an unfinished hour, else `:raw`
  (ingested, compacted, or the out-of-hour `-edge-` rows of a finalization).
  `:catalog` objects list an hour's series for discovery
  (`Pulse.Storage.S3.MetricCatalog`) and hold no samples. Their keys also
  contain `-rollup-`, so releases that predate them treat them as rollups:
  never read as samples, only retired by an hour's finalization.
  Readers before `:grouped` existed treat those segments as raw, which they
  read correctly.
  """
  def metric_tier(%__MODULE__{key: key}), do: key_tier(key)

  def key_tier(key) do
    base = Path.basename(key)

    cond do
      String.contains?(base, "-catalog-") -> :catalog
      String.contains?(base, "-rollup-") -> :rollup
      String.contains?(base, "-final-") -> :final
      String.contains?(base, "-group-") -> :grouped
      true -> :raw
    end
  end

  @doc """
  Compile storage matchers once per query for `matches_metrics?/2`. Sample
  queries never see rollup or catalog objects; `tier: :rollup` and
  `tier: :catalog` select only those.
  """
  def metrics_filter(matchers, tier \\ :samples)
  def metrics_filter({:metric_plan, _, _, _} = plan, _tier), do: plan

  def metrics_filter(matchers, tier) do
    plan = MetricLabelSummary.plan(matchers)

    # Name matchers a bloom can decide: each needs one of these names present.
    names =
      for {"__name__", op, expected} <- plan,
          alternatives = bloom_names(op, expected),
          alternatives != nil,
          do: Enum.map(alternatives, &name_hash/1)

    {:metric_plan, plan, names, tier}
  end

  defp bloom_names(:eq, ""), do: nil
  defp bloom_names(:eq, name), do: [name]

  defp bloom_names(:re, {exact, []}) do
    if not MapSet.member?(exact, ""), do: MapSet.to_list(exact)
  end

  defp bloom_names(_op, _expected), do: nil

  @doc """
  Prune metrics only when a complete name or label value set proves that some
  matcher (equality, inequality, or a recognized regex shape) cannot match, or
  a name bloom proves that no name an equality or literal alternation accepts
  is present.
  """
  def matches_metrics?(segment, {:metric_plan, plan, names, tier}) do
    in_tier?(metric_tier(segment), tier) and matches_plan?(segment, plan, names)
  end

  def matches_metrics?(segment, matchers), do: matches_metrics?(segment, metrics_filter(matchers))

  defp in_tier?(actual, :samples), do: actual not in [:rollup, :catalog]
  defp in_tier?(actual, tier), do: actual == tier

  defp matches_plan?(segment, plan, names) do
    MetricLabelSummary.satisfiable?(plan, fn
      "__name__" when is_list(segment.metric_names) -> {:ok, segment.metric_names}
      "__name__" -> :error
      _name when segment.metric_labels == nil -> :error
      name -> Map.fetch(segment.metric_labels, name)
    end) and bloom_may_match?(segment, names)
  end

  defp bloom_may_match?(%__MODULE__{metric_names: nil, metric_name_bloom: bits}, names) when is_binary(bits),
    do: Enum.all?(names, fn hashes -> Enum.any?(hashes, &bloom_member?(bits, &1)) end)

  defp bloom_may_match?(_segment, _names), do: true

  defp valid_services([_ | _] = services) do
    if length(services) <= 128 and
         Enum.all?(services, &(is_binary(&1) and byte_size(&1) in 1..256)),
       do: services
  end

  defp valid_services(_), do: nil

  # Stream labels summarized per log segment, in priority order: the label
  # summary's byte budget drops later names first. These are the labels Loki
  # pushes from Alloy/Promtail commonly carry, plus Pulse's error labels.
  @log_label_names ~w(error_source error_project cluster namespace container service_name env job pod app instance)

  @doc "Attach a complete bounded set of nonempty promoted log services, or leave it unknown."
  def summarize_logs(segment, records) do
    services = Enum.reduce_while(records, MapSet.new(), &collect_log_service/2)

    services = if services, do: services |> Enum.map(&:binary.copy/1) |> Enum.sort()

    # Atom or invalid UTF-8 keys can normalize during JSON encoding; only
    # summarize maps whose key identity is unchanged at the native boundary.
    valid_resources? =
      Enum.all?(records, fn record ->
        Enum.all?(Map.keys(record.resource || %{}), &(is_binary(&1) and String.valid?(&1)))
      end)

    labels =
      if valid_resources? do
        records
        |> Enum.map(&%{labels: Map.new(@log_label_names, fn name -> {name, log_label_value(&1, name)} end)})
        |> MetricLabelSummary.build(@log_label_names)
      end

    minutes = if Enum.all?(records, &is_integer(&1.timestamp_ns)), do: log_minutes(Enum.map(records, & &1.timestamp_ns))
    %{segment | log_services: services, log_labels: labels, log_minutes: minutes}
  end

  @doc """
  Summaries of a stream-grouped log segment from what the native grouper
  reports (`Pulse.Storage.S3.LogTiers`): its complete service set, its
  distinct `{service, resource_json}` streams and line counts per minute,
  each `nil` when unknown. Labels are read as `summarize_logs/2` reads them.
  """
  def summarize_log_streams(segment, services, streams, minutes) do
    resources = streams && Enum.map(streams, fn {service, resource} -> {service, decode_resource(resource)} end)

    labels =
      if resources && Enum.all?(resources, &is_map(elem(&1, 1))) do
        resources
        |> Enum.map(fn {service, resource} ->
          record = %{service: service, resource: resource}
          %{labels: Map.new(@log_label_names, &{&1, log_label_value(record, &1)})}
        end)
        |> MetricLabelSummary.build(@log_label_names)
      end

    %{
      segment
      | log_services: services && valid_services(services),
        log_labels: labels,
        log_minutes: minutes && Map.new(minutes)
    }
  end

  defp decode_resource(json) do
    case Pulse.JSON.decode(json) do
      {:ok, %{} = resource} -> resource
      _ -> nil
    end
  end

  @doc "Stream-label summary of a segment holding exactly the rows of segments with `summaries`."
  def merge_log_labels(summaries), do: MetricLabelSummary.union(summaries, @log_label_names)

  @doc """
  Wire summary of a manifest page's active log segments, so planning can skip
  the whole page: their complete service and stream-label sets (`"ls"`,
  `"el"`). Each is omitted when any segment's is unknown or the union is too
  large, labels first, since root references repeat it on every append. `nil`
  when neither is known.
  """
  @page_summary_bytes 2048
  def log_page_summary(segments) do
    # Rollups are planned with `log_rollups: true`, which ignores summaries.
    segments = Enum.reject(segments, &(key_tier(&1.key) == :rollup))

    services =
      if Enum.all?(segments, &is_list(&1.log_services)) do
        services = segments |> Enum.flat_map(& &1.log_services) |> Enum.uniq() |> Enum.sort()
        if length(services) <= 128, do: services
      end

    labels = merge_log_labels(Enum.map(segments, & &1.log_labels))

    [%{"ls" => services, "el" => labels}, %{"ls" => services}]
    |> Enum.map(&Map.put(Map.reject(&1, fn {_, v} -> is_nil(v) end), "v", 1))
    |> Enum.find(&(map_size(&1) > 1 and IO.iodata_length(Pulse.JSON.encode_to_iodata!(&1)) <= @page_summary_bytes))
  end

  @doc "Whether a page with `log_page_summary/1` summary `wire` may hold a segment matching `opts`."
  def log_page_matches?(%{"v" => 1} = wire, opts) do
    # A page summary never describes the rollups it may also hold.
    opts[:log_rollups] == true or
      summary_matches?(
        %__MODULE__{log_services: valid_services(wire["ls"]), log_labels: MetricLabelSummary.parse(wire["el"])},
        opts
      )
  end

  def log_page_matches?(_wire, _opts), do: true

  # The value the native matcher sees for `name` (`matchers_pass` in
  # segment_parquet.rs): `service_name` prefers a nonempty promoted service,
  # every other summarized name reads the top-level resource string. A missing
  # label is "", as in LogQL. Non-string values stay unknown independently:
  # atoms in particular become strings at the JSON/native boundary.
  # A non-string promoted service is returned as is, so the label stays unknown.
  defp log_label_value(%{service: service}, "service_name") when service not in [nil, ""], do: service
  defp log_label_value(record, name), do: Map.get(record.resource || %{}, name, "")

  defp collect_log_service(%{service: service}, services) when is_binary(service) and byte_size(service) in 1..256 do
    services = MapSet.put(services, service)
    if MapSet.size(services) <= 128, do: {:cont, services}, else: {:halt, nil}
  end

  defp collect_log_service(_record, _services), do: {:halt, nil}

  @doc """
  Prune service and stream-label selectors only with complete summaries.

  Equality and inequality matchers compare against the summarized values.
  Regex matchers need `opts[:log_label_regexes]` from `compile_log_matchers/1`
  (the native matcher's own regex engine); without it they never prune.
  """
  def matches_log_service?(%__MODULE__{} = segment, opts) do
    # Log rollups (`-rollup-` keys) are read only by rollup planning.
    if opts[:log_rollups], do: key_tier(segment.key) == :rollup, else: log_segment_matches?(segment, opts)
  end

  defp log_segment_matches?(segment, opts), do: key_tier(segment.key) != :rollup and summary_matches?(segment, opts)

  # The pushed-down service (`opts[:service]`) is also a `service_name`
  # equality: the label summary's effective values cover every stored
  # service, so it prunes segments whose service set is unknown because some
  # of their lines have no service.
  defp summary_matches?(segment, opts) do
    matchers = Keyword.get(opts, :matchers, [])
    matchers = if service = opts[:service], do: [{"service_name", :eq, service} | matchers], else: matchers

    service_matches?(segment.log_services, opts) and
      log_labels_match?(segment.log_labels, matchers, opts[:log_label_regexes] || %{})
  end

  @doc """
  Compile the regex stream matchers of a log query once per query, with the
  regex engine the native segment matcher uses, for `matches_log_service?/2`.
  Patterns that do not compile are left out and so never prune.
  """
  def compile_log_matchers(opts) do
    regexes =
      for {name, op, pattern} <- Keyword.get(opts, :matchers, []),
          op in [:re, :nre],
          name in @log_label_names,
          into: %{} do
        case NIF.compile_log_regex(pattern) do
          {:ok, regex} -> {pattern, regex}
          _ -> {pattern, nil}
        end
      end

    if map_size(regexes) == 0, do: opts, else: Keyword.put(opts, :log_label_regexes, regexes)
  end

  defp log_labels_match?(nil, _matchers, _regexes), do: true

  defp log_labels_match?(summary, matchers, regexes) do
    Enum.all?(matchers, fn {name, op, value} ->
      case Map.fetch(summary, name) do
        {:ok, values} -> Enum.any?(values, &label_value_matches?(op, value, &1, regexes))
        :error -> true
      end
    end)
  end

  defp label_value_matches?(:eq, expected, value, _regexes), do: value == expected
  defp label_value_matches?(:neq, expected, value, _regexes), do: value != expected

  defp label_value_matches?(op, pattern, value, regexes) do
    case Map.get(regexes, pattern) do
      nil -> true
      regex -> regex_matches?(pattern, regex, value) == (op == :re)
    end
  end

  # Summaries repeat the same few values across thousands of segments; one
  # native call per distinct pattern/value pair, bounded per process. A
  # pattern always compiles to the same program, so entries never go stale.
  @regex_memo {__MODULE__, :regex_memo}
  defp regex_matches?(pattern, regex, value) do
    memo = Process.get(@regex_memo, %{})

    case memo do
      %{{^pattern, ^value} => matched} ->
        matched

      _ ->
        matched = NIF.match_log_regex(regex, value)
        if map_size(memo) < 4096, do: Process.put(@regex_memo, Map.put(memo, {pattern, value}, matched))
        matched
    end
  end

  defp service_matches?(nil, _opts), do: true

  defp service_matches?(services, opts) do
    direct = Keyword.get(opts, :service)
    matchers = Keyword.get(opts, :matchers, [])

    Enum.any?(services, fn service ->
      (is_nil(direct) or service == direct) and
        Enum.all?(matchers, fn
          {name, :eq, value} when name in ["service", "service_name"] -> service == value
          _ -> true
        end)
    end)
  end

  defp valid_non_neg(v) when is_integer(v) and v >= 0, do: v
  defp valid_non_neg(_), do: nil
end
