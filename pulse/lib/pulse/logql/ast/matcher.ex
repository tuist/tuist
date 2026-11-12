defmodule Pulse.LogQL.AST.Matcher do
  @moduledoc """
  A single label matcher inside a stream selector: `name<op>"value"`.

  `op` is one of `:eq | :neq | :re | :nre`, matching LogQL's `=`, `!=`,
  `=~`, `!~`.
  """

  @enforce_keys [:name, :op, :value]
  defstruct [:name, :op, :value]

  @type op :: :eq | :neq | :re | :nre

  @type t :: %__MODULE__{
          name: String.t(),
          op: op(),
          value: String.t()
        }
end
