defmodule Pulse.Record.Log do
  @moduledoc """
  Internal representation of a single log record after decoding from OTLP.

  Timestamps are Unix nanoseconds. `service` and `severity_text` are surfaced
  as top-level fields because they are the most common filter dimensions;
  structured values live in `body`, `attributes` and `resource`. `otlp` retains
  typed AnyValues, instrumentation scope, schema URLs, flags, dropped counts and
  event names. Legacy and Loki records have no OTLP envelope.
  """

  # `timestamp_ns` may be nil at decode time — the OTLP spec allows both
  # `time_unix_nano` and `observed_time_unix_nano` to be absent, and it
  # explicitly treats a value of 0 as "unknown". The receiver uses observed
  # time when event time is unknown. Both unknown leaves nil during decode;
  # unkeyed HTTP preparation uses receive time, while keyed requests require
  # an effective timestamp. The OTLP envelope retains the original times.
  defstruct [
    :timestamp_ns,
    :observed_timestamp_ns,
    :severity_number,
    :severity_text,
    :service,
    :body,
    :trace_id,
    :span_id,
    :otlp,
    attributes: %{},
    resource: %{}
  ]

  @type t :: %__MODULE__{
          timestamp_ns: integer() | nil,
          observed_timestamp_ns: integer() | nil,
          severity_number: non_neg_integer() | nil,
          severity_text: String.t() | nil,
          service: String.t() | nil,
          body: term(),
          otlp: map() | nil,
          trace_id: String.t() | nil,
          span_id: String.t() | nil,
          attributes: %{optional(String.t()) => term()},
          resource: %{optional(String.t()) => term()}
        }
end
