defmodule Pulse.LogQL.AST.LabelReplace do
  @moduledoc """
  Metric label rewriting: `label_replace(inner, dst, replacement, src, regex)`.
  """

  @enforce_keys [:inner, :dst, :replacement, :src, :regex]
  defstruct [:inner, :dst, :replacement, :src, :regex]

  @type t :: %__MODULE__{
          inner: term(),
          dst: String.t(),
          replacement: String.t(),
          src: String.t(),
          regex: String.t()
        }
end
