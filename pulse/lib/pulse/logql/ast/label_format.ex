defmodule Pulse.LogQL.AST.LabelFormat do
  @moduledoc """
  `| label_format new="template", other=source` stage.

  Each entry is either:

    * `{name, {:template, str}}` — the label is set to the result of
      evaluating the Go-template string against the current label bag.
    * `{name, {:rename, source}}` — the label is set from another label
      and the source label is removed.
  """

  @enforce_keys [:entries]
  defstruct entries: []

  @type entry :: {String.t(), {:template, String.t()} | {:rename, String.t()}}
  @type t :: %__MODULE__{entries: [entry()]}
end
