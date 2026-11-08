defmodule Pulse.LogQL.AST.RangeAgg do
  @moduledoc """
  Range aggregation over a log query: `rate({...}[5m])`,
  `count_over_time({...}[1h] offset 5m)`,
  `quantile_over_time(0.99, {...} | unwrap dur [5m])`.

  `range_ns` is the duration in nanoseconds; `offset_ns` is the
  optional `offset` modifier; `at_ns` is the optional `@ <timestamp>`
  modifier (absolute epoch time in nanoseconds). `param` is the
  quantile's numeric argument or the `approx_count_distinct` field name.
  """

  alias Pulse.LogQL.AST.Grouping
  alias Pulse.LogQL.AST.LogQuery

  @enforce_keys [:op, :inner, :range_ns]
  defstruct [:op, :inner, :range_ns, offset_ns: nil, at_ns: nil, param: nil, grouping: nil]

  @type op ::
          :rate
          | :rate_counter
          | :count_over_time
          | :approx_count_distinct
          | :bytes_over_time
          | :bytes_rate
          | :sum_over_time
          | :avg_over_time
          | :max_over_time
          | :min_over_time
          | :stddev_over_time
          | :stdvar_over_time
          | :quantile_over_time
          | :first_over_time
          | :last_over_time
          | :absent_over_time

  @type t :: %__MODULE__{
          op: op(),
          inner: LogQuery.t(),
          range_ns: integer(),
          offset_ns: integer() | nil,
          at_ns: integer() | nil,
          param: number() | String.t() | nil,
          grouping: Grouping.t() | nil
        }
end
