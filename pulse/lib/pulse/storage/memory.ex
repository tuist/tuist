defmodule Pulse.Storage.Memory do
  @moduledoc """
  In-memory signal storage backed by a public ETS table.

  Test-only adapter. Meant to prove the ingest → storage → query spine
  end to end without dragging in Rust, Parquet, or S3. Dev and prod use
  `Pulse.Storage.S3`; this module stays wired as the default in
  `mix test` because `config/test.exs` sets no adapter override.

  Records for each `(tenant, signal)` are kept in a private list, appended
  to as batches arrive and scanned linearly on query. That is deliberately
  naive: we want to burn nothing on this adapter that we would not throw
  away when Parquet lands.
  """

  @behaviour Pulse.Storage

  use Pulse.Runtime.GenServer

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Record.Span
  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.SortOrder

  @table __MODULE__

  @spec start_link(keyword()) :: Elixir.GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Every table operation goes through the current runtime's instance name.
  defp table, do: Pulse.Runtime.table(@table)

  @impl Pulse.Storage
  def append(signal, tenant, records, _opts \\ []) when is_atom(signal) and is_binary(tenant) and is_list(records) do
    key = {tenant, signal}

    existing =
      case :ets.lookup(table(), key) do
        [{^key, list}] -> list
        [] -> []
      end

    :ets.insert(table(), {key, existing ++ Pulse.JSON.detach(records)})
    :ok
  end

  @impl Pulse.Storage
  def query(signal, tenant, opts) when is_atom(signal) and is_binary(tenant) and is_list(opts) do
    key = {tenant, signal}

    records =
      case :ets.lookup(table(), key) do
        [{^key, list}] -> list
        [] -> []
      end

    {matchers, filters} = query_filters(signal, opts)

    filtered =
      records
      |> filter_by_time(Keyword.get(opts, :start_ts), Keyword.get(opts, :end_ts))
      |> filter_by_service(Keyword.get(opts, :service))
      |> filter_spans(opts)
      |> filter_by_matchers(matchers)
      |> filter_by_line_filters(filters)
      |> filter_exemplars(Keyword.get(opts, :exemplars, false))
      |> SortOrder.sort(signal)
      |> take_limit(Keyword.get(opts, :limit))

    case Keyword.get(opts, :max_records) do
      max when is_integer(max) and length(filtered) > max -> {:error, :query_sample_limit}
      _ -> {:ok, filtered}
    end
  end

  defp filter_exemplars(records, false), do: records
  defp filter_exemplars(records, true), do: Enum.filter(records, &(&1.exemplars not in [nil, []]))

  @impl Pulse.Storage
  def put_metric_metadata(tenant, entries, today) do
    {:ok, set} = metric_metadata(tenant)
    :ets.insert(table(), {{tenant, :metric_metadata}, Pulse.MetricMetadata.merge(set, entries, today)})
    :ok
  end

  @impl Pulse.Storage
  def metric_metadata(tenant) do
    case :ets.lookup(table(), {tenant, :metric_metadata}) do
      [{_, set}] -> {:ok, set}
      [] -> {:ok, %{}}
    end
  end

  @doc """
  Select log records exactly as `query/3` does for the `:service`,
  `:matchers` and `:line_filters` options, compiling each regex once. Live
  tailing uses it so tailed and queried records agree.
  """
  @spec select_logs([Log.t()], keyword()) :: [Log.t()]
  def select_logs(records, opts) do
    records
    |> filter_by_service(Keyword.get(opts, :service))
    |> filter_by_matchers(Enum.map(Keyword.get(opts, :matchers, []), &compile_matcher/1))
    |> filter_by_line_filters(Enum.map(Keyword.get(opts, :line_filters, []), &compile_line_filter/1))
  end

  defp query_filters(:logs, opts) do
    {Enum.map(Keyword.get(opts, :matchers, []), &compile_matcher/1),
     Enum.map(Keyword.get(opts, :line_filters, []), &compile_line_filter/1)}
  end

  defp query_filters(_signal, opts), do: {Keyword.get(opts, :matchers, []), Keyword.get(opts, :line_filters, [])}

  defp compile_matcher({name, op, pattern}) when op in [:re, :nre], do: {name, op, compile_regex!(pattern)}
  defp compile_matcher(matcher), do: matcher

  defp compile_line_filter({op, pattern}) when op in [:match_re, :not_match_re], do: {op, compile_regex!(pattern)}
  defp compile_line_filter(filter), do: filter

  @doc false
  @spec reset() :: :ok
  def reset do
    if :ets.info(table()) != :undefined do
      :ets.delete_all_objects(table())
    end

    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  defp filter_by_time(records, nil, nil), do: records

  defp filter_by_time(records, start_ts, end_ts) do
    Enum.filter(records, fn record ->
      # A nil timestamp does not fit inside a time-bounded range. Elixir's
      # term ordering puts atoms greater than numbers, so `nil >= 5` is
      # true without an explicit guard — leaving nil-ts records leaking
      # through every time filter.
      ts = record_ts(record)

      is_integer(ts) and
        (start_ts == nil or ts >= start_ts) and
        (end_ts == nil or ts <= end_ts)
    end)
  end

  defp record_ts(%Log{timestamp_ns: ts}), do: ts
  defp record_ts(%MetricSample{timestamp_ns: ts}), do: ts
  defp record_ts(%Span{timestamp_ns: ts}), do: ts

  defp filter_spans(records, opts) do
    Enum.filter(records, fn
      %Span{} = s -> Span.matches?(s, opts)
      _ -> true
    end)
  end

  # Logs-only convenience filter — metric samples have no `service`
  # field so a service filter is undefined for them; pass them through
  # unchanged rather than silently drop them.
  defp filter_by_service(records, nil), do: records

  defp filter_by_service(records, service) do
    Enum.filter(records, fn
      %Log{service: s} -> s == service
      %Span{service: s} -> s == service
      %MetricSample{} -> true
    end)
  end

  # Selector-matcher parity with the S3 Rust pushdown. Every matcher must
  # pass. Missing labels are treated as the empty string, matching Loki
  # semantics: `foo=""` matches records with no `foo` label.
  defp filter_by_matchers(records, []), do: records

  defp filter_by_matchers(records, matchers) do
    Enum.filter(records, fn record ->
      Enum.all?(matchers, &matcher_matches?(&1, record))
    end)
  end

  defp matcher_matches?({name, op, value}, record) do
    raw = label_from_record(record, name)
    label_value = if is_binary(raw), do: raw, else: ""

    if match?(%MetricSample{}, record) and op in [:re, :nre] do
      matched = NIF.match_metric_regex(value, label_value)
      if op == :re, do: matched, else: not matched
    else
      apply_matcher_op(op, label_value, value)
    end
  end

  @doc false
  def log_matcher_value(record, name) do
    case label_from_record(record, name) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  # Logs: promoted typed fields first (service, service_name, level,
  # detected_level), then resource JSON. Attributes are NOT consulted —
  # they are per-record structured metadata, not stream labels, and
  # mixing them here would diverge from the S3 Rust decoder which only
  # reads resource + promoted columns. Callers who want to filter on
  # attributes use the post-parse label filter (`| foo = "bar"`) which
  # runs over the full merged bag in the pipeline.
  #
  # Metrics: labels live in the `labels` map directly — there is no
  # separation of "stream" vs "structured" labels in the Prometheus
  # data model.
  defp label_from_record(%Log{} = record, name) do
    promoted_field(record, name) || Map.get(record.resource || %{}, name)
  end

  defp label_from_record(%MetricSample{labels: labels}, name), do: Map.get(labels, name)

  # Empty promoted values are absent, so the resource is consulted, as in Rust.
  defp promoted_field(%Log{} = record, name) when name in ["service", "service_name"], do: present(record.service)

  defp promoted_field(%Log{} = record, name) when name in ["level", "detected_level"], do: present(record.severity_text)

  defp promoted_field(_record, _name), do: nil

  defp present(""), do: nil
  defp present(value), do: value

  defp apply_matcher_op(:eq, actual, wanted), do: actual == wanted
  defp apply_matcher_op(:neq, actual, wanted), do: actual != wanted
  defp apply_matcher_op(:re, actual, pattern), do: regex_match?(pattern, actual)
  defp apply_matcher_op(:nre, actual, pattern), do: not regex_match?(pattern, actual)

  # Invalid regexes are caught by `Pulse.LogQL.QueryValidation` before the
  # storage layer runs. If we somehow get here with one, raise rather
  # than silently invert to `true` for the `:nre` / `:not_match_re` op.
  defp regex_match?({:native_regex, re}, subject), do: NIF.match_log_regex(re, subject)
  defp regex_match?(pattern, subject), do: regex_match?(compile_regex!(pattern), subject)

  defp compile_regex!(pattern) do
    case NIF.compile_log_regex(pattern) do
      {:ok, re} -> {:native_regex, re}
      :error -> raise ArgumentError, "invalid regex #{inspect(pattern)}"
    end
  end

  # Line-filter parity with the S3 Rust decoder. Body normalization
  # mirrors `Pulse.LogQL.Entry.from_record/1` and Rust's
  # `line_bytes_for_match`: a string body is matched directly; a
  # non-string body is JSON-encoded first so both paths agree on what
  # "the log line" means. Metric samples have no `body`, so line
  # filters pass them through unchanged.
  defp filter_by_line_filters(records, []), do: records

  defp filter_by_line_filters(records, filters) do
    Enum.filter(records, fn
      %MetricSample{} ->
        true

      record ->
        body = line_from_record(record)
        Enum.all?(filters, &line_filter_matches?(&1, body))
    end)
  end

  @doc false
  def line_from_record(%{body: nil}), do: ""
  def line_from_record(%{body: body}) when is_binary(body), do: body
  def line_from_record(%{body: body}), do: Pulse.JSON.encode!(body)

  defp line_filter_matches?({:contains, needle}, body), do: String.contains?(body, needle)
  defp line_filter_matches?({:not_contains, needle}, body), do: not String.contains?(body, needle)
  defp line_filter_matches?({:match_re, pattern}, body), do: regex_match?(pattern, body)
  defp line_filter_matches?({:not_match_re, pattern}, body), do: not regex_match?(pattern, body)

  defp take_limit(records, nil), do: records
  defp take_limit(records, limit) when is_integer(limit) and limit > 0, do: Enum.take(records, limit)
end
