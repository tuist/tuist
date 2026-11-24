defmodule Symptoms.Evidence.Record do
  @moduledoc """
  One evidence record per `(entity, source, window)`, as described in
  `symptoms/README.md` "Evidence record".

  - `entity`: the entity the evidence is about (for example
    `%{environment: "production", service: "tuist-server", kind: "route", key: "POST /api/..."}`).
  - `phenomenon`: one of `phenomena/0`.
  - `source`: the stream that produced it, for example `"trace.error_betabinomial"`.
  - `window_start`, `window_seconds`: the window the statistic covers.
  - `statistic`: the raw statistic (a residual or share; see `Symptoms.Evidence.Statistics`).
  - `e`: the calibrated, capped e-value (see `Symptoms.Evidence.Calibration`).
  - `observed`, `expected`, `n`: what was seen, the baseline expectation and the
    window's denominator (requests, events), when they apply.
  - `impact`: `%{unit: String.t(), rate: number}`. When a flow is missing, `rate`
    is the expected baseline volume.
  - `examples`: at most 3 IDs (trace, event or issue IDs), never raw text.
  """

  alias Symptoms.Evidence.Calibration

  @phenomena [:request_errors, :latency, :saturation, :availability, :platform_events, :novelty]
  @max_examples 3

  @enforce_keys [:entity, :phenomenon, :source, :window_start, :window_seconds, :statistic, :e]
  defstruct [
    :entity,
    :phenomenon,
    :source,
    :window_start,
    :window_seconds,
    :statistic,
    :e,
    :observed,
    :expected,
    :n,
    :impact,
    examples: []
  ]

  @type phenomenon ::
          :request_errors | :latency | :saturation | :availability | :platform_events | :novelty
  @type impact :: %{unit: String.t(), rate: number()}
  @type t :: %__MODULE__{
          entity: term(),
          phenomenon: phenomenon(),
          source: String.t(),
          window_start: DateTime.t(),
          window_seconds: pos_integer(),
          statistic: number(),
          e: number(),
          observed: number() | nil,
          expected: number() | nil,
          n: non_neg_integer() | nil,
          impact: impact() | nil,
          examples: [String.t()]
        }

  @doc "The phenomena an evidence record can belong to."
  @spec phenomena() :: [phenomenon()]
  def phenomena, do: @phenomena

  @doc """
  Builds and validates a record from a map or keyword list.

  Returns `{:error, {field, reason}}` for the first invalid field: an unknown
  phenomenon, a non-positive window, an e-value outside `0..Calibration.cap()`,
  more than #{@max_examples} examples or non-string examples, or an impact
  without a string `unit` and a non-negative `rate`.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, {atom(), atom()}}
  def new(attrs) do
    attrs = Map.new(attrs)

    with :ok <- check(:phenomenon, attrs[:phenomenon] in @phenomena),
         :ok <- check(:source, is_binary(attrs[:source])),
         :ok <- check(:window_start, match?(%DateTime{}, attrs[:window_start])),
         :ok <- check(:window_seconds, is_integer(attrs[:window_seconds]) and attrs[:window_seconds] > 0),
         :ok <- check(:statistic, is_number(attrs[:statistic])),
         :ok <- check(:e, valid_e?(attrs[:e])),
         :ok <- check(:examples, valid_examples?(Map.get(attrs, :examples, []))),
         :ok <- check(:impact, valid_impact?(attrs[:impact])) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  defp check(_field, true), do: :ok
  defp check(field, false), do: {:error, {field, :invalid}}

  defp valid_e?(e), do: is_number(e) and e >= 0 and e <= Calibration.cap()

  defp valid_examples?(examples) do
    is_list(examples) and length(examples) <= @max_examples and Enum.all?(examples, &is_binary/1)
  end

  defp valid_impact?(nil), do: true
  defp valid_impact?(%{unit: unit, rate: rate}), do: is_binary(unit) and is_number(rate) and rate >= 0
  defp valid_impact?(_), do: false
end
