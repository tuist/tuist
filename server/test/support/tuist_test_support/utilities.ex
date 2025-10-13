defmodule TuistTestSupport.Utilities do
  @moduledoc ~S"""
  A module that provides functions for testing.
  """
  alias Tuist.CommandEvents.Buffer
  alias Tuist.Runs.Build
  alias Tuist.Runs.BuildFile
  alias Tuist.Runs.BuildIssue
  alias Tuist.Runs.BuildTarget

  def unique_integer(length \\ 3) do
    System.unique_integer([:positive, :monotonic]) + (10 |> :math.pow(length - 1) |> round())
  end

  @doc """
  Flushes the ingestion buffers after running the callback function.
  """
  def with_flushed_ingestion_buffers(fun) when is_function(fun, 0) do
    result = fun.()
    Buffer.flush()
    Build.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()
    result
  end

  def truncate_clickhouse_tables do
    # Ensure all buffers are flushed before truncating to prevent race conditions.
    Buffer.flush()
    Build.Buffer.flush()
    BuildIssue.Buffer.flush()
    BuildFile.Buffer.flush()
    BuildTarget.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()

    commands = [
      "TRUNCATE TABLE IF EXISTS build_runs",
      "TRUNCATE TABLE IF EXISTS command_events",
      "TRUNCATE TABLE IF EXISTS xcode_graphs",
      "TRUNCATE TABLE IF EXISTS xcode_projects",
      "TRUNCATE TABLE IF EXISTS xcode_targets"
    ]

    for command <- commands do
      Tuist.IngestRepo.query!(command)
    end
  end
end
