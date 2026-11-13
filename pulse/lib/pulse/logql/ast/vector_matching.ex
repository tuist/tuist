defmodule Pulse.LogQL.AST.VectorMatching do
  @moduledoc """
  Modifier on a binary operator between two vector expressions:
  `... on (a, b) group_left (c) ...` or `... ignoring (x) ...`.
  """

  @enforce_keys [:mode]
  defstruct [:mode, labels: [], group: nil, group_labels: []]

  @type mode :: :on | :ignoring
  @type group :: nil | :left | :right

  @type t :: %__MODULE__{
          mode: mode(),
          labels: [String.t()],
          group: group(),
          group_labels: [String.t()]
        }
end
