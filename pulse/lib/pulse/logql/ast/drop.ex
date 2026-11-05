defmodule Pulse.LogQL.AST.Drop do
  @moduledoc """
  `| drop label1, label2="value", label3=~"re"` stage.

  Each entry is `{name, match}` where `match` is `:any` (drop when the
  label exists) or a `{op, value}` tuple to drop when the predicate
  holds — the same value shape as `Pulse.LogQL.AST.LabelFilter`.
  """

  @enforce_keys [:entries]
  defstruct entries: []

  @type match ::
          :any
          | {:eq, String.t()}
          | {:neq, String.t()}
          | {:re, String.t()}
          | {:nre, String.t()}

  @type entry :: {String.t(), match()}
  @type t :: %__MODULE__{entries: [entry()]}
end
