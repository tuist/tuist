defmodule TuistTestSupport.Utilities do
  @moduledoc ~S"""
  A module that provides functions for testing.
  """
  def unique_integer(length \\ 3) do
    System.unique_integer([:positive, :monotonic]) + (10 |> :math.pow(length - 1) |> round())
  end

  @doc """
  Flushes the ingestion buffers after running the callback function.
  """
  def with_flushed_ingestion_buffers(fun) when is_function(fun, 0) do
    result = fun.()
    Tuist.CommandEvents.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()
    result
  end

  def truncate_clickhouse_tables do
    commands = [
      "TRUNCATE TABLE IF EXISTS command_events",
      "TRUNCATE TABLE IF EXISTS xcode_graphs",
      "TRUNCATE TABLE IF EXISTS xcode_projects",
      "TRUNCATE TABLE IF EXISTS xcode_targets",
      "TRUNCATE TABLE IF EXISTS cacheable_tasks",
      "TRUNCATE TABLE IF EXISTS cas_outputs",
      "TRUNCATE TABLE IF EXISTS cas_events",
      "TRUNCATE TABLE IF EXISTS build_files",
      "TRUNCATE TABLE IF EXISTS build_issues",
      "TRUNCATE TABLE IF EXISTS build_targets"
    ]

    for command <- commands do
      Tuist.IngestRepo.query!(command)
    end
  end
end
