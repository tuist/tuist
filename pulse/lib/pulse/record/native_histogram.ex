defmodule Pulse.Record.NativeHistogram do
  @moduledoc """
  A Prometheus native histogram sample, in the float form PromQL computes
  with (Prometheus's `FloatHistogram`).

    * `schema` — the bucket resolution: `-4..8` for exponential buckets, where
      bucket `i` holds `(base^(i-1), base^i]` with `base = 2^(2^-schema)`, or
      `-53` for custom bounds listed in `custom_values`.
    * `zero_threshold`, `zero_count` — the zero bucket `[-threshold, threshold]`.
    * `count`, `sum` — total observations and their sum.
    * `positive_spans`, `negative_spans` — `{offset, length}` runs of populated
      bucket indexes; the first offset is the first index, later offsets are
      gaps after the previous run.
    * `positive_buckets`, `negative_buckets` — absolute counts, one per index
      the spans cover (never deltas).
    * `counter_reset_hint` — `:unknown`, `:yes`, `:no` or `:gauge`.

  Ingest converts integer histograms, whose buckets arrive as deltas, into
  this form. Counts are floats so rates and averages stay exact operations.
  """

  defstruct schema: 0,
            zero_threshold: 0.0,
            zero_count: 0.0,
            count: 0.0,
            sum: 0.0,
            positive_spans: [],
            positive_buckets: [],
            negative_spans: [],
            negative_buckets: [],
            counter_reset_hint: :unknown,
            custom_values: []

  @type span :: {integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          schema: integer(),
          zero_threshold: float(),
          zero_count: float(),
          count: float(),
          sum: float() | :stale | :nan | :infinity | :negative_infinity,
          positive_spans: [span()],
          positive_buckets: [float()],
          negative_spans: [span()],
          negative_buckets: [float()],
          counter_reset_hint: :unknown | :yes | :no | :gauge,
          custom_values: [float()]
        }

  @doc "Schema of histograms with custom bucket bounds (`custom_values`)."
  def custom_buckets_schema, do: -53
end
