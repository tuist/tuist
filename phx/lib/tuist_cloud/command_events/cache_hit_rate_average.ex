defmodule TuistCloud.CommandEvents.CacheHitRateAverage do
  @moduledoc """
  A struct that represents the average cache hit rate of a command event.
  """
  @enforce_keys [:date, :value, :runs_count]
  defstruct [:date, :value, :runs_count]
end
