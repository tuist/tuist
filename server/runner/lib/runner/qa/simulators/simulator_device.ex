defmodule Runner.QA.Simulators.SimulatorDevice do
  @moduledoc """
  Represents a simulator device.
  """

  defstruct [:name, :udid, :state, :runtime_identifier]
end
