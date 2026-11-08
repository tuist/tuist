defmodule Pulse.LogQL.AST.Unwrap do
  @moduledoc """
  `| unwrap label` or `| unwrap duration(label)` / `unwrap bytes(label)`.

  Selects a numeric label value for the range aggregator wrapping this
  log query. `conversion` is one of `:none | :duration_seconds |
  :duration | :bytes` — Loki's `duration_seconds` and `duration` both
  parse Go durations (with `duration_seconds` returning seconds and
  `duration` returning seconds too, historically, but we keep them
  distinct in the AST so the evaluator can honour whichever Loki
  version's semantics the query expects).
  """

  @enforce_keys [:label]
  defstruct [:label, conversion: :none]

  @type conversion :: :none | :duration_seconds | :duration | :bytes
  @type t :: %__MODULE__{label: String.t(), conversion: conversion()}
end
