defmodule Tuist.CI do
  @moduledoc """
  Context module for CI-related functionality.
  """

  alias Tuist.CI.JobRun

  def list_job_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(JobRun, attrs, for: JobRun)
  end
end
