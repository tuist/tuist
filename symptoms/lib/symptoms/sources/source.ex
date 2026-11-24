defmodule Symptoms.Sources.Source do
  @moduledoc """
  A source of raw evidence. The pipeline (`Symptoms.Pipeline`) calls every
  configured source once per window; a source returns one record per entity
  with its raw `statistic` and `e: 0.0`. The pipeline calibrates `e` against
  the stream's history (`Symptoms.Evidence.Calibration`), so sources never set
  it.

  A source that could not read its input for the window returns
  `{:unknown, entities}` for the entities it expected, so the pipeline marks
  them unknown rather than quiet (README "Presence").

  Options every source in `Symptoms.Sources` accepts (all optional; a source
  ignores what it does not use):

  - `:environment`: the entity environment, default `"production"`.
  - `:entities`: the entities the pipeline expects for this source (from the
    catalogue); returned in `{:unknown, entities}` and used to notice series
    that vanished.
  - `:baseline`: `(stream :: String.t(), entity :: map()) -> term() | nil`,
    the stored baseline for one stream of one entity. Each source documents
    the shape and offers a function that computes it from its input, so the
    pipeline can refresh and store it on the README cadence. `nil` means the
    entity is new: it gets novelty evidence only.
  - `:known?`: `(entity :: map()) -> boolean()`, whether the catalogue already
    has the entity (novelty rules).
  - `:unknown`: `(stream :: String.t(), entities :: [map()]) -> any()`. When
    only part of a window lacks input (one stream, or some entities), a source
    returns `{:ok, records}` for the rest and calls this with the missing part,
    so it is still marked unknown.
  - `:discovered`: `(entities :: [map()]) -> any()`, entities seen without a
    baseline, for the catalogue (they borrow a family baseline and count only
    for novelty in their first hour).
  - `:now`: Unix seconds, for sources that compare against the clock.

  `:unknown`, `:discovered` and the options above extend the original
  contract compatibly: the callbacks are unchanged, and a pipeline that passes
  none of them still gets `{:ok, records}`, `{:unknown, entities}` or
  `{:error, reason}` as before.
  """

  alias Symptoms.Evidence.Record

  @type window :: %{start: integer(), seconds: pos_integer()}
  @type change :: %{
          kind: :deploy | :config,
          ref: String.t(),
          at: integer(),
          service: String.t() | nil,
          touched_entities: [map()],
          before: term(),
          after: term()
        }

  @doc "Stable source name, used as `Record.source` prefix and in weights."
  @callback name() :: String.t()

  @doc "Window lengths this source produces, in seconds (60 or 300)."
  @callback window_seconds() :: pos_integer()

  @callback collect(window(), opts :: keyword()) ::
              {:ok, [Record.t()]} | {:unknown, [map()]} | {:error, term()}

  @doc "Change events in the window. Only change sources implement it."
  @callback changes(window(), opts :: keyword()) :: {:ok, [change()]} | {:error, term()}

  @optional_callbacks changes: 2
end
