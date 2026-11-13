defmodule Pulse.LogQL.AST.Keep do
  @moduledoc """
  `| keep label1, label2="value"` stage.

  Same entry shape as `Pulse.LogQL.AST.Drop`, but the semantics flip:
  the evaluator keeps only labels named in the list (and, when a
  predicate is supplied, only when it holds).
  """

  alias Pulse.LogQL.AST.Drop

  @enforce_keys [:entries]
  defstruct entries: []

  @type t :: %__MODULE__{entries: [Drop.entry()]}
end
