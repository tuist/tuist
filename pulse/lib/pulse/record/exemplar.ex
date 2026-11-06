defmodule Pulse.Record.Exemplar do
  @moduledoc """
  A Prometheus exemplar: one observation behind a metric sample, usually
  carrying the trace that produced it (`trace_id`, `span_id` labels).

  Exemplars are stored on the metric sample of their series nearest to them
  in time (`Pulse.Record.MetricSample`'s `exemplars`), keeping their own
  timestamp. As in Prometheus, their label set may hold at most 128 UTF-8
  characters across names and values.
  """

  defstruct labels: %{}, value: 0.0, timestamp_ns: 0

  @type t :: %__MODULE__{
          labels: %{optional(String.t()) => String.t()},
          value: float() | :nan | :infinity | :negative_infinity,
          timestamp_ns: integer()
        }

  @doc "Prometheus' limit on an exemplar's label set, in UTF-8 characters."
  def max_label_set_length, do: 128
end
