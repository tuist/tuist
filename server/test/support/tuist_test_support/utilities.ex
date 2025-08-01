defmodule TuistTestSupport.Utilities do
  @moduledoc ~S"""
  A module that provides functions for testing.
  """
  def unique_integer(length \\ 3) do
    System.unique_integer([:positive, :monotonic]) + (10 |> :math.pow(length - 1) |> round())
  end

  @doc """
  Flushes the command events ingestion buffer after running the callback function.
  """
  def with_flushed_command_events(fun) when is_function(fun, 0) do
    result = fun.()
    Tuist.CommandEvents.Buffer.flush()
    result
  end
end
