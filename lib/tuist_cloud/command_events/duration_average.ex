defmodule TuistCloud.CommandEvents.DurationAverage do
  @moduledoc """
  A struct that represents the average duration of a command event.
  """
  @enforce_keys [:date, :value, :runs_count]
  defstruct [:date, :value, :runs_count]
end
