defmodule Pulse.LogQL.AST.VectorAgg do
  @moduledoc """
  Vector aggregation: `sum by (svc) (...)`, `topk(5, ...)`, `avg without (pod) (...)`.

  `inner` is another metric expression (`RangeAgg`, `VectorAgg`,
  `BinaryOp`, or `NumberLit`). `grouping` is optional. `param` is the
  scalar argument for `topk`/`bottomk`/`approx_topk` (an integer).
  """

  alias Pulse.LogQL.AST.Grouping

  @enforce_keys [:op, :inner]
  defstruct [:op, :inner, grouping: nil, param: nil]

  @type op ::
          :sum
          | :avg
          | :min
          | :max
          | :count
          | :stddev
          | :stdvar
          | :topk
          | :approx_topk
          | :bottomk
          | :sort
          | :sort_desc

  @type t :: %__MODULE__{
          op: op(),
          inner: term(),
          grouping: Grouping.t() | nil,
          param: integer() | nil
        }
end
