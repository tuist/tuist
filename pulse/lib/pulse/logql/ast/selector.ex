defmodule Pulse.LogQL.AST.Selector do
  @moduledoc """
  Stream selector: the `{name="value", other=~"re"}` prefix of a log
  query.

  Every LogQL expression starts with a selector; the parser rejects a
  bare `{}` because an unbounded selector would scan every segment.
  """

  alias Pulse.LogQL.AST.Matcher

  @enforce_keys [:matchers]
  defstruct matchers: []

  @type t :: %__MODULE__{matchers: [Matcher.t()]}
end
