defmodule Pulse.Record.MetricSample do
  @moduledoc """
  One Prometheus-style metric sample: a label set, a timestamp, and a value.

  By convention the metric name lives inside `labels` under `"__name__"`,
  which matches the Prometheus data model and keeps the wire boundary
  thin: the `remote_write` decoder promotes every label pair into this
  map as-is, no field splitting.

  `series_id` is the stable 64-bit fingerprint of the label set, computed
  by the Rust codec (Pulse's port of Prometheus's `labels.StableHash`). It
  is left `nil` at wire-decode time and filled in before Parquet encode.
  Readers should treat `series_id` as a pruning accelerator only — identity
  is the canonical labels, not the hash.

  Values unsupported by BEAM floats use the closed atoms `:stale`, `:nan`,
  `:infinity`, and `:negative_infinity`. The native codec preserves the stale
  NaN payload exactly through Parquet and compaction. Ordinary NaN payloads
  normalize to `:nan`; they are arithmetic values, not staleness markers.

  A native histogram sample has `value: nil` and its histogram in `histogram`
  (`Pulse.Record.NativeHistogram`). `exemplars` lists the exemplars stored on
  this sample (`Pulse.Record.Exemplar`), or is `nil`.

  `timestamp_ns` is nanoseconds since the Unix epoch. The wire protocols
  (Prometheus remote_write v1 and OTLP metrics) express timestamps in
  milliseconds and nanoseconds respectively; conversion happens at the
  wire boundary so the storage path only ever sees nanoseconds.

  `start_timestamp_ms` retains a Remote Write 2.0 source start/created time,
  or is nil when unset. It stays in signed int64 milliseconds to preserve the
  complete wire domain without nanosecond overflow. It is not a sample time,
  series label, retention bound or instruction to synthesize a zero sample.
  """

  alias Pulse.Record.Exemplar
  alias Pulse.Record.NativeHistogram

  defstruct [:series_id, :timestamp_ns, :value, :otlp, :histogram, :exemplars, :start_timestamp_ms, labels: %{}]

  @type t :: %__MODULE__{
          series_id: non_neg_integer() | nil,
          timestamp_ns: integer() | nil,
          start_timestamp_ms: integer() | nil,
          value: number() | :stale | :nan | :infinity | :negative_infinity | nil,
          labels: %{optional(String.t()) => String.t()},
          otlp: map() | nil,
          histogram: NativeHistogram.t() | nil,
          exemplars: [Exemplar.t()] | nil
        }
end
