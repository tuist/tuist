defmodule Pulse.LogQL.AST.BinaryOp do
  @moduledoc """
  Binary operator between two metric expressions.

  `bool` is set when the query uses the `bool` modifier on a comparison
  operator, which turns the comparison into a 0/1 scalar rather than
  filtering the vector. `matching` carries an optional
  `Pulse.LogQL.AST.VectorMatching` modifier.
  """

  alias Pulse.LogQL.AST.VectorMatching

  @enforce_keys [:op, :left, :right]
  defstruct [:op, :left, :right, bool: false, matching: nil]

  @type op ::
          :add
          | :sub
          | :mul
          | :div
          | :mod
          | :pow
          | :eq
          | :neq
          | :lt
          | :lte
          | :gt
          | :gte
          | :and
          | :or
          | :unless

  @type t :: %__MODULE__{
          op: op(),
          left: term(),
          right: term(),
          bool: boolean(),
          matching: VectorMatching.t() | nil
        }
end
