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
    flush_ingestion_buffers()
    result
  end

  def flush_ingestion_buffers do
    Tuist.CommandEvents.Event.Buffer.flush()
    Tuist.Gradle.Build.Buffer.flush()
    Tuist.Gradle.Task.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()
    Tuist.Builds.Build.Buffer.flush()
    flush_test_buffers()
  end

  def flush_test_buffers do
    Tuist.Tests.TestCase.Buffer.flush()
    Tuist.Tests.TestCaseRun.Buffer.flush()
    Tuist.Tests.TestModuleRun.Buffer.flush()
    Tuist.Tests.TestSuiteRun.Buffer.flush()
    Tuist.Tests.TestCaseFailure.Buffer.flush()
    Tuist.Tests.TestCaseRunRepetition.Buffer.flush()
    Tuist.Tests.TestCaseEvent.Buffer.flush()
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
      "TRUNCATE TABLE IF EXISTS build_targets",
      "TRUNCATE TABLE IF EXISTS build_runs",
      "TRUNCATE TABLE IF EXISTS gradle_builds",
      "TRUNCATE TABLE IF EXISTS gradle_tasks",
      "TRUNCATE TABLE IF EXISTS gradle_cache_events"
    ]

    for command <- commands do
      Tuist.IngestRepo.query!(command)
    end
  end
end
