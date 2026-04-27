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
    Tuist.Bundles.ArtifactIngest.Buffer.flush()
    result
  end
end
