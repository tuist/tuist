defmodule Pulse.LogQL.AST.LabelFilter do
  @moduledoc """
  Predicate on parsed labels: `| status_code >= 500`, `| env="prod"`,
  `| duration > 1s`, composed with `and` / `or`.

  Parsed into a small tree so evaluation is straightforward and the
  precedence resolved by the parser is preserved in the AST:

      expr ::= {:cmp, name, op, value}
             | {:and, expr, expr}
             | {:or, expr, expr}

  `op` on a `:cmp` node is one of `:eq | :neq | :re | :nre | :lt |
  :lte | :gt | :gte`. `value` is a tagged tuple so the evaluator does
  not have to re-guess the type:

      {:string, str}
      {:re, pattern}
      {:ip, pattern}            # `=ip(...)` / `!=ip(...)`
      {:number, integer | float}
      {:duration_ns, integer}   # `1s`, `500ms`, `1h30m` etc, resolved to ns
      {:bytes, integer}         # `5MB`, `1KiB`, `2GB`, resolved to bytes
  """

  @enforce_keys [:expr]
  defstruct [:expr]

  @type cmp_op :: :eq | :neq | :re | :nre | :lt | :lte | :gt | :gte
  @type value ::
          {:string, String.t()}
          | {:re, String.t()}
          | {:ip, String.t()}
          | {:number, integer() | float()}
          | {:duration_ns, integer()}
          | {:bytes, integer()}

  @type expr ::
          {:cmp, String.t(), cmp_op(), value()}
          | {:and, expr(), expr()}
          | {:or, expr(), expr()}

  @type t :: %__MODULE__{expr: expr()}
end
