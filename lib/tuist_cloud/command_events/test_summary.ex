defmodule TuistCloud.CommandEvents.TestSummary do
  @moduledoc ~S"""
  A module that represents the test summary.
  """

  defstruct [
    :target_tests,
    :failed_tests_count,
    :successful_tests_count,
    :total_tests_count
  ]
end
