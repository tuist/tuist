defmodule Tuist.Performance do
  @moduledoc ~S"""
  A set of functions to measure the performance of code.
  """
  def measure_time_in_milliseconds(fun) do
    {time_us, result} = :timer.tc(fun)
    {Timex.Duration.to_milliseconds(time_us, :microseconds), result}
  end
end
