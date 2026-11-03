defmodule Atlas.Signals.Config do
  @moduledoc "Operator-controlled activation after every Orbit/Automation replica is compatible."

  def enabled?, do: Application.get_env(:atlas, :signals_enabled, false)
end
