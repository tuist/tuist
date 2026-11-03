defmodule Tuist.TestImpactAnalysis.Rule do
  @moduledoc """
  A step of the selection pipeline (`Tuist.TestImpactAnalysis`). A rule reads
  the input and the decisions so far, decides some of the undecided tests,
  and says whether the pipeline goes on. It does no writes and no reads of its
  own, so the same input always gives the same decisions.
  """
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @type verdict :: :continue | :done | {:abort, reason :: atom(), matched_path :: String.t() | nil}

  @doc "The rule's name, as the trace records it and as the reason of the tests it decides."
  @callback name() :: atom()

  @callback decide(Input.t(), State.t()) :: {State.t(), verdict()}
end
