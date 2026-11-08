defmodule Pulse.Reliability.Provider do
  @moduledoc """
  Provider boundary for bounded service-summary assessments.

  Providers select classifications and fixed query identifiers, never executable
  queries or infrastructure actions. Scheduling, budgets and persistence belong
  to the caller.
  """

  @callback assess(map(), keyword()) :: {:ok, map()} | {:error, term()}
end
