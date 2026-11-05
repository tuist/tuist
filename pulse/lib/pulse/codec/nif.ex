defmodule Pulse.Codec.NIF do
  @moduledoc false

  # Byte-heavy encoding and decoding in Rust (`native/pulse_codec`): Loki
  # push protobuf, JSON (behind `Pulse.JSON`), and log segments (behind
  # `Pulse.Storage.S3` and `Pulse.MCP.Tools`). Distributed the same way as
  # `Pulse.ObjectStore.NIF`: precompiled artifacts from GitHub Releases for
  # consumers, compiled from source when `PULSE_NIF_FORCE_BUILD` is set
  # (local dev and CI).
  use RustlerPrecompiled,
    otp_app: :pulse,
    crate: "pulse_codec",
    base_url: "https://github.com/tuist/tuist/releases/download/pulse@#{Mix.Project.config()[:version]}",
    force_build: System.get_env("PULSE_NIF_FORCE_BUILD") in ["1", "true"],
    version: Mix.Project.config()[:version],
    targets: ~w(
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      aarch64-apple-darwin
    ),
    nif_versions: ~w(2.16)

  @doc false
  def ensure_log_metadata_api! do
    ensure_otlp_wire_api!()

    version =
      try do
        {log_metadata_api_version(), log_discovery_api_version(), log_metric_api_version()}
      rescue
        ErlangError -> :unavailable
      end

    if version != {1, 1, 19} do
      raise "codec native artifact cannot preserve OTLP log metadata, discover log stream labels, mine log patterns, skip absent unwrap values before prior pipeline errors, preserve typed label-filter errors, decode logfmt fields and parser label ownership, count/replace template regex matches, preserve erased regexp captures, nest flag-separated repetitions, support numeric/repeated selector capture names and numeric parser labels, admit Unicode 17 property names and membership, preserve scalar class complements, expose correlation IDs as LogQL metadata or run keep and post-unwrap error filters natively; rebuild with PULSE_NIF_FORCE_BUILD=1 or install the matching release artifacts"
    end

    :ok
  end

  def otlp_wire_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def native_allocated_bytes, do: :erlang.nif_error(:nif_not_loaded)
  def native_malloc_stats, do: :erlang.nif_error(:nif_not_loaded)
  def native_malloc_trim, do: :erlang.nif_error(:nif_not_loaded)

  def ensure_otlp_wire_api! do
    version =
      try do
        otlp_wire_api_version()
      rescue
        ErlangError -> :unavailable
      end

    if version != 3 do
      raise "codec native artifact cannot decode bounded OTLP protobuf merges, exact JSON integers and scoped duplicate fields; rebuild with PULSE_NIF_FORCE_BUILD=1 or install matching release artifacts"
    end

    :ok
  end

  def log_metadata_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def log_discovery_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def log_metric_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def log_metric_scan_new(_stages, _value, _drop, _grouping, _max_samples), do: :erlang.nif_error(:nif_not_loaded)
  def log_metric_binned_new(_value, _grouping, _max_samples), do: :erlang.nif_error(:nif_not_loaded)

  def log_metric_scan_rollup(_scan, _blob, _buckets, _service, _matchers), do: :erlang.nif_error(:nif_not_loaded)

  # Per-minute log rollups (`Pulse.Storage.S3.LogRollups`); tier API 2.
  def log_rollup_new(_start, _end, _buckets), do: :erlang.nif_error(:nif_not_loaded)
  def log_rollup_add(_rollup, _blob, _segment?, _buckets), do: :erlang.nif_error(:nif_not_loaded)
  def log_rollup_finish(_rollup, _sources), do: :erlang.nif_error(:nif_not_loaded)
  def log_rollup_sources(_blob), do: :erlang.nif_error(:nif_not_loaded)

  def log_metric_scan_add(_scan, _blob, _start, _finish, _service, _matchers, _line_filters),
    do: :erlang.nif_error(:nif_not_loaded)

  def log_metric_scan_finish(_scan), do: :erlang.nif_error(:nif_not_loaded)
  def log_metric_scan_abort(_scan), do: :erlang.nif_error(:nif_not_loaded)
  def log_pattern_scan_new(_start, _step), do: :erlang.nif_error(:nif_not_loaded)
  def log_pattern_observe(_scan, _lines), do: :erlang.nif_error(:nif_not_loaded)
  def log_pattern_finish(_scan), do: :erlang.nif_error(:nif_not_loaded)
  def trace_metrics_api_version, do: :erlang.nif_error(:nif_not_loaded)

  def trace_metrics_new(_program, _root_only, _op, _quantiles, _value, _by, _window, _second),
    do: :erlang.nif_error(:nif_not_loaded)

  def trace_metrics_add(_metrics, _blob, _floor), do: :erlang.nif_error(:nif_not_loaded)
  def trace_metrics_finish(_metrics), do: :erlang.nif_error(:nif_not_loaded)
  def trace_metrics_batch_new(_leaves), do: :erlang.nif_error(:nif_not_loaded)
  def trace_metrics_batch_finish(_metrics), do: :erlang.nif_error(:nif_not_loaded)
  def log_discovery_new(_mode, _key, _start, _finish, _service, _matchers), do: :erlang.nif_error(:nif_not_loaded)
  def log_discovery_add(_state, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def log_discovery_finish(_state), do: :erlang.nif_error(:nif_not_loaded)
  def log_discovery_abort(_state), do: :erlang.nif_error(:nif_not_loaded)

  def ensure_trace_metadata_api! do
    ensure_otlp_wire_api!()

    version =
      try do
        {{trace_metadata_api_version(), trace_search_api_version(), tempo_trace_api_version(),
          tempo_search_api_version(), tempo_discovery_api_version()}, trace_metrics_api_version()}
      rescue
        ErlangError -> :unavailable
      end

    if version != {{2, 1, 3, 7, 12}, 6},
      do:
        raise(
          "codec native artifact cannot validate typed OTLP trace metadata and run bounded trace-level search/Tempo trace export/scoped discovery/metrics with shared expression budgets, directional string-group ranking ties and scalar prefilters before ranking, event-scope predicates, structural operators and select; rebuild with PULSE_NIF_FORCE_BUILD=1 or install matching release artifacts"
        )

    :ok
  end

  def trace_metadata_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def trace_payload_size(_records, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_discovery_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def tempo_filtered_discovery_new(_floor, _scope, _key, _predicates), do: :erlang.nif_error(:nif_not_loaded)

  def tempo_windowed_discovery_new(_floor, _scope, _key, _predicates, _start, _end),
    do: :erlang.nif_error(:nif_not_loaded)

  def tempo_discovery_new(_floor, _scope, _key), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_discovery_add(_state, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_discovery_finish(_state), do: :erlang.nif_error(:nif_not_loaded)

  def tempo_search_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_new(_floor, _start, _end, _predicates, _limit, _spss), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_expression_search_new(_floor, _start, _end, _program, _limit, _spss), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_add(_search, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_add_unplanned(_search, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_plan_seal(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_plan_hashes(_search, _hashes), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_plan_may_match(_search, _hashes, _bits), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_finish(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_finish_window(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_root_discovery_new(_floor, _key, _predicates, _start, _end), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_root_discovery_finish(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_trace_duration_discovery_new(_floor, _predicates, _start, _end), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_trace_duration_discovery_finish(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_search_abort(_search), do: :erlang.nif_error(:nif_not_loaded)
  def tempo_trace_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def tempo_trace_export(_assembly, _format), do: :erlang.nif_error(:nif_not_loaded)
  def trace_search_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def trace_search_new(_start, _finish, _predicates, _limit, _max_groups), do: :erlang.nif_error(:nif_not_loaded)
  def trace_search_add(_search, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def trace_search_finish(_search), do: :erlang.nif_error(:nif_not_loaded)

  def ensure_metric_metadata_api! do
    ensure_otlp_wire_api!()

    version =
      try do
        {metric_metadata_api_version(), otlp_metrics_api_version(), metric_postings_api_version(),
         metric_discovery_api_version(), metric_footer_api_version()}
      rescue
        ErlangError -> :unavailable
      end

    if version != {2, 2, 1, 1, 1},
      do:
        raise(
          "codec native artifact cannot preserve metric metadata and remote-write start timestamps, encode metric postings, discover metric labels and plan metric footer reads; rebuild with PULSE_NIF_FORCE_BUILD=1 or install matching release artifacts"
        )

    :ok
  end

  def metric_metadata_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def otlp_metrics_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def metric_postings_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def metric_discovery_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def metric_footer_api_version, do: :erlang.nif_error(:nif_not_loaded)

  def metric_segment_footer_plan(_tail, _size, _start, _finish, _matchers), do: :erlang.nif_error(:nif_not_loaded)
  def metric_discovery_new(_mode, _key, _start, _finish, _selectors), do: :erlang.nif_error(:nif_not_loaded)
  def metric_discovery_add(_state, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def metric_discovery_finish(_state), do: :erlang.nif_error(:nif_not_loaded)
  def metric_discovery_abort(_state), do: :erlang.nif_error(:nif_not_loaded)
  def metric_segment_parquet_row_count(_blob), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Hour finalization and rollups (`Pulse.Storage.S3.MetricTiers`).
  def ensure_metric_tier_api! do
    version =
      try do
        metric_tier_api_version()
      rescue
        ErlangError -> :unavailable
      end

    if version != 2,
      do:
        raise(
          "codec native artifact cannot finalize partitioned metric hours, consolidate metric segments, read metric rollups or build and read log rollups; rebuild with PULSE_NIF_FORCE_BUILD=1 or install matching release artifacts"
        )

    :ok
  end

  @doc false
  # Stream-grouped log segments (`Pulse.Storage.S3.LogTiers`).
  def ensure_log_tier_api! do
    version =
      try do
        log_tier_api_version()
      rescue
        ErlangError -> :unavailable
      end

    if version != 1,
      do:
        raise(
          "codec native artifact cannot group log segments by service; rebuild with PULSE_NIF_FORCE_BUILD=1 or install matching release artifacts"
        )

    :ok
  end

  def log_tier_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def log_group_new(_target_rows, _target_bytes, _pack_bytes, _max_held), do: :erlang.nif_error(:nif_not_loaded)
  def log_group_add(_grouper, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def log_group_next(_grouper, _finish), do: :erlang.nif_error(:nif_not_loaded)

  def metric_tier_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def metric_finalize_new(_start, _end, _max_rows, _expected_rows, _partition), do: :erlang.nif_error(:nif_not_loaded)
  def metric_finalize_add(_finalizer, _blob), do: :erlang.nif_error(:nif_not_loaded)

  def metric_finalize_finish(_finalizer, _target_rows, _rollup_target_rows, _max_names),
    do: :erlang.nif_error(:nif_not_loaded)

  def metric_finalize_next(_finalizer), do: :erlang.nif_error(:nif_not_loaded)

  def decode_metric_rollups(_blob, _start, _finish, _matchers), do: :erlang.nif_error(:nif_not_loaded)

  def decode_loki_push(_compressed, _max_decompressed_bytes), do: :erlang.nif_error(:nif_not_loaded)

  def decode_loki_push_limited(_compressed, _max_decompressed_bytes, _limits), do: :erlang.nif_error(:nif_not_loaded)
  def json_decode(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def json_decode_dirty(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def json_encode(_term, _budget), do: :erlang.nif_error(:nif_not_loaded)
  def json_encode_dirty(_term), do: :erlang.nif_error(:nif_not_loaded)
  def encode_log_segment(_records, _mode, _framing), do: :erlang.nif_error(:nif_not_loaded)
  def decode_log_segment(_blob, _start_ts, _end_ts, _service), do: :erlang.nif_error(:nif_not_loaded)
  # Versioned bindings prevent an old precompiled artifact from silently
  # acknowledging records after dropping the new OTLP metadata column.
  def encode_log_segment_parquet(records), do: encode_log_segment_parquet_v2(records)
  def encode_log_segment_parquet_v2(_records), do: :erlang.nif_error(:nif_not_loaded)

  def decode_log_segment_parquet(blob, start_ts, end_ts, service, matchers, line_filters),
    do: decode_log_segment_parquet_v2(blob, start_ts, end_ts, service, matchers, line_filters)

  def decode_log_segment_parquet_v2(_blob, _start_ts, _end_ts, _service, _matchers, _line_filters),
    do: :erlang.nif_error(:nif_not_loaded)

  def otlp_json_decode(_body), do: :erlang.nif_error(:nif_not_loaded)

  def decode_log_segment_parquet_bounded(_blob, _start_ts, _end_ts, _service, _matchers, _line_filters, _max_records),
    do: :erlang.nif_error(:nif_not_loaded)

  def decode_log_segment_parquet_limited(
        _blob,
        _start_ts,
        _end_ts,
        _service,
        _matchers,
        _line_filters,
        _max_records,
        _max_decoded_bytes
      ), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def otlp_json_decode_scoped(_body, _signal), do: :erlang.nif_error(:nif_not_loaded)
  def otlp_json_negative_zero(_body), do: :erlang.nif_error(:nif_not_loaded)
  def decode_otlp_logs(_body, _limits), do: :erlang.nif_error(:nif_not_loaded)
  def decode_otlp_metrics(_body, _limits), do: :erlang.nif_error(:nif_not_loaded)
  def metric_metadata_size(_records, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def log_payload_size(_records, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def encode_log_segment_bounded(_records, _limit), do: :erlang.nif_error(:nif_not_loaded)

  def decode_otlp_traces(_body, _limits), do: :erlang.nif_error(:nif_not_loaded)
  def encode_trace_segment_parquet(_spans), do: :erlang.nif_error(:nif_not_loaded)
  def encode_trace_segment_parquet_v2(_spans), do: :erlang.nif_error(:nif_not_loaded)
  def compact_trace_segments(_blobs, _max_rows), do: :erlang.nif_error(:nif_not_loaded)
  def compact_log_segments(_blobs, _max_rows), do: :erlang.nif_error(:nif_not_loaded)

  def log_segment_reader_new(_blob, _start_ts, _end_ts, _service, _matchers, _line_filters),
    do: :erlang.nif_error(:nif_not_loaded)

  def log_segment_reader_next(_reader, _min_records), do: :erlang.nif_error(:nif_not_loaded)
  def log_segment_parquet_row_count(_blob), do: :erlang.nif_error(:nif_not_loaded)
  def compact_trace_segments_v2(_blobs, _max_rows), do: :erlang.nif_error(:nif_not_loaded)

  def compact_trace_segments_split(_blobs, _max_rows, _max_ids, _max_flagged_ids, _max_output_rows),
    do: :erlang.nif_error(:nif_not_loaded)

  def trace_segment_parquet_row_count(_blob), do: :erlang.nif_error(:nif_not_loaded)
  def trace_query_new(_start, _finish, _filters, _fields, _max), do: :erlang.nif_error(:nif_not_loaded)
  def trace_query_new_trace(_trace_id, _retention_floor, _max), do: :erlang.nif_error(:nif_not_loaded)
  def trace_query_add(_query, _blob), do: :erlang.nif_error(:nif_not_loaded)
  def trace_query_finish(_query, _max_results), do: :erlang.nif_error(:nif_not_loaded)
  def trace_query_finish_trace(_query, _max_results, _trace_id), do: :erlang.nif_error(:nif_not_loaded)

  def decode_trace_segment_parquet(_blob, _start, _finish, _filters, _max_records),
    do: :erlang.nif_error(:nif_not_loaded)

  def encode_metric_segment_parquet(samples), do: encode_metric_segment_parquet_v2(samples)
  def encode_metric_segment_parquet_v2(_samples), do: :erlang.nif_error(:nif_not_loaded)
  def encode_metric_segment_parquet_indexed_v1(_samples), do: :erlang.nif_error(:nif_not_loaded)

  def decode_metric_segment_parquet(blob, start_ts, end_ts, matchers),
    do: decode_metric_segment_parquet_v2(blob, start_ts, end_ts, matchers)

  def decode_metric_segment_parquet_v2(_blob, _start_ts, _end_ts, _matchers), do: :erlang.nif_error(:nif_not_loaded)

  def decode_metric_segment_parquet_bounded(blob, start_ts, end_ts, matchers, max_samples),
    do: decode_metric_segment_parquet_bounded_v2(blob, start_ts, end_ts, matchers, max_samples)

  def decode_metric_segment_parquet_bounded_v2(_blob, _start_ts, _end_ts, _matchers, _max_samples),
    do: :erlang.nif_error(:nif_not_loaded)

  def compile_metric_capture_regex(_pattern), do: :erlang.nif_error(:nif_not_loaded)
  def compile_log_regex(_pattern), do: :erlang.nif_error(:nif_not_loaded)
  def filter_log_regex(_regex, _rows, _negate), do: :erlang.nif_error(:nif_not_loaded)
  def match_log_regex(_regex, _value), do: :erlang.nif_error(:nif_not_loaded)
  def log_regex_named_capture?(_regex), do: :erlang.nif_error(:nif_not_loaded)
  def log_regex_named_captures(_regex, _value), do: :erlang.nif_error(:nif_not_loaded)
  def log_regex_count(_pattern, _value, _max_work), do: :erlang.nif_error(:nif_not_loaded)

  def log_regex_replace(_pattern, _value, _replacement, _literal?, _max_work, _max_output),
    do: :erlang.nif_error(:nif_not_loaded)

  def metric_regex_captures(_regex, _value), do: :erlang.nif_error(:nif_not_loaded)
  def validate_metric_regex(_pattern), do: :erlang.nif_error(:nif_not_loaded)
  def validate_log_regex(_pattern), do: :erlang.nif_error(:nif_not_loaded)
  def match_metric_regex(_pattern, _value), do: :erlang.nif_error(:nif_not_loaded)

  # Hand-rolled Prometheus remote_write v1 wire decoder: takes a
  # Snappy-compressed `prometheus.WriteRequest` protobuf and a cap on the
  # decompressed size, returns `{:ok, series}` where each series is
  # `{labels_map, samples_list, series_id}` with `samples_list` as
  # `[{timestamp_ms, value}]`. Zero-copy over the decompressed buffer; the
  # Elixir caller converts to `%MetricSample{}` and ns units.
  def decode_remote_write(_compressed, _max_decompressed_bytes), do: :erlang.nif_error(:nif_not_loaded)

  def decode_remote_write_limited(_compressed, _max_decompressed_bytes, _limits), do: :erlang.nif_error(:nif_not_loaded)

  # Remote Write 2.0 `io.prometheus.write.v2.Request`: same series envelope,
  # but samples/histograms are `{timestamp_ms, value, start_timestamp_ms | nil}`.
  def decode_remote_write_v2_limited(_compressed, _max_decompressed_bytes, _limits),
    do: :erlang.nif_error(:nif_not_loaded)

  # Like `decode_metric_segment_parquet_v2`, keeping only samples with exemplars.
  def decode_metric_exemplars_parquet(_blob, _start_ts, _end_ts, _matchers), do: :erlang.nif_error(:nif_not_loaded)

  # Rust fast-path JSON encoder for the MCP `query_metrics` response.
  # Returns `{:ok, binary}` on success or `:fallback` when the input
  # is not a well-shaped `[%Pulse.Record.MetricSample{}]`; the Elixir
  # caller falls back to `JSON.encode!` in that case.
  def encode_metric_samples(_samples), do: :erlang.nif_error(:nif_not_loaded)
end
