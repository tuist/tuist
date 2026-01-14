defmodule Tuist.Runs.FlakyTestCase do
  @moduledoc """
  A virtual schema representing aggregated flaky test case data.
  This is used to display test cases that have had flaky runs.
  """

  defstruct [:id, :name, :module_name, :suite_name, :flaky_runs_count, :last_flaky_at, :last_flaky_run_id]
end
