defmodule Tuist.CommandEvents.TargetTestSummary do
  @moduledoc ~S"""
  A module that represents a test summary for a given target.
  """

  defstruct [
    :tests,
    :status
  ]
end
