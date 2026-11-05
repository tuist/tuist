defmodule Pulse.LogQL.AST.LogQuery do
  @moduledoc """
  A complete log query: a stream selector followed by an ordered list of
  pipeline stages.

  A LogQuery evaluated on its own produces streams. A LogQuery wrapped in
  a `Pulse.LogQL.AST.RangeAgg` produces a matrix; the range aggregator
  reads its `Unwrap` stage (when present, always the last stage) to
  decide which numeric value to reduce.
  """

  alias Pulse.LogQL.AST.Decolorize
  alias Pulse.LogQL.AST.Drop
  alias Pulse.LogQL.AST.JsonParser
  alias Pulse.LogQL.AST.Keep
  alias Pulse.LogQL.AST.LabelFilter
  alias Pulse.LogQL.AST.LabelFormat
  alias Pulse.LogQL.AST.LineFilter
  alias Pulse.LogQL.AST.LineFormat
  alias Pulse.LogQL.AST.LogfmtParser
  alias Pulse.LogQL.AST.PatternParser
  alias Pulse.LogQL.AST.RegexpParser
  alias Pulse.LogQL.AST.Selector
  alias Pulse.LogQL.AST.UnpackParser
  alias Pulse.LogQL.AST.Unwrap

  @enforce_keys [:selector]
  defstruct [:selector, stages: []]

  @type stage ::
          LineFilter.t()
          | LabelFilter.t()
          | JsonParser.t()
          | LogfmtParser.t()
          | RegexpParser.t()
          | PatternParser.t()
          | UnpackParser.t()
          | LineFormat.t()
          | LabelFormat.t()
          | Drop.t()
          | Keep.t()
          | Decolorize.t()
          | Unwrap.t()

  @type t :: %__MODULE__{selector: Selector.t(), stages: [stage()]}
end
