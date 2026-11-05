defmodule Pulse.LogQL.AST.Grouping do
  @moduledoc """
  `by (labels)` or `without (labels)` modifier on a vector aggregation.
  """

  @enforce_keys [:mode]
  defstruct [:mode, labels: []]

  @type mode :: :by | :without
  @type t :: %__MODULE__{mode: mode(), labels: [String.t()]}
end
