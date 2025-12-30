defmodule Runner.QA.Sleeper do
  @moduledoc """
  Wrapper module for Process.sleep to enable easier testing by stubbing this module
  instead of trying to stub Process directly.
  """

  @doc """
  Sleep for the given number of milliseconds.
  """
  def sleep(milliseconds) do
    Process.sleep(milliseconds)
  end
end
