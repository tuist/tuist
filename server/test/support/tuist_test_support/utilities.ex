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
    Tuist.CommandEvents.Event.Buffer.flush()
    Tuist.Gradle.Build.Buffer.flush()
    Tuist.Gradle.Task.Buffer.flush()
    Tuist.Xcode.XcodeGraph.Buffer.flush()
    Tuist.Xcode.XcodeProject.Buffer.flush()
    Tuist.Xcode.XcodeTarget.Buffer.flush()
    Tuist.Builds.Build.Buffer.flush()
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
      "TRUNCATE TABLE IF EXISTS build_targets",
      "TRUNCATE TABLE IF EXISTS build_runs",
      "TRUNCATE TABLE IF EXISTS gradle_builds",
      "TRUNCATE TABLE IF EXISTS gradle_tasks",
      "TRUNCATE TABLE IF EXISTS gradle_cache_events"
    ]

    for command <- commands do
      query_with_retry(command)
    end
  end

  # ClickHouse occasionally drops idle pool connections under CI load; the Ch
  # client reestablishes them transparently on the *next* use, but the call in
  # flight when that happens still raises `Mint.TransportError: socket closed`.
  # Retry once on that specific error so an `on_exit` TRUNCATE doesn't fail
  # the test that just finished.
  defp query_with_retry(command, attempts_left \\ 1) do
    Tuist.IngestRepo.query!(command)
  rescue
    error in DBConnection.ConnectionError ->
      if attempts_left > 0 and error.reason in [:socket_closed, "socket closed"] do
        query_with_retry(command, attempts_left - 1)
      else
        reraise error, __STACKTRACE__
      end

    error in Mint.TransportError ->
      if attempts_left > 0 and error.reason == :closed do
        query_with_retry(command, attempts_left - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
