defmodule Tuist.QA.SimulatorDevice do
  @moduledoc """
  Represents a simulator device.
  """

  defstruct [:name, :udid, :state, :runtime_identifier]
end
