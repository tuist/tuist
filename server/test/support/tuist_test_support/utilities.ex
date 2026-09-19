defmodule TuistTestSupport.Utilities do
  @moduledoc ~S"""
  A module that provides functions for testing.
  """
  def unique_integer(length \\ 3) do
    System.unique_integer([:positive, :monotonic]) + (10 |> :math.pow(length - 1) |> round())
  end

  @doc """
  The attributes of an Ecto struct that `insert_all/2` accepts: the schema's
  real fields only. Drops `__meta__`, associations, and virtual fields, which
  a struct read back from a query carries alongside its columns.
  """
  def insertable_attrs(%schema{} = struct) do
    Map.take(struct, schema.__schema__(:fields))
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
end
