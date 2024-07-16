defmodule Tuist.CommandEvents.TestSummary do
  @moduledoc ~S"""
  A module that represents the test summary.
  """

  defstruct [
    :project_tests,
    :failed_tests_count,
    :successful_tests_count,
    :total_tests_count
  ]
end
