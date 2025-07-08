defmodule Tuist.CommandEvents.ResultBundle.ActionTestableSummary do
  @moduledoc """
  A summary of the tests for a target.
  """
  defstruct [:module_name, :tests, :project_identifier]
end
