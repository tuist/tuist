defmodule Tuist.Mix do
  @moduledoc ~S"""
  This module represents a boundary for all the Mix tasks.
  """
  use Boundary, deps: [Tuist]
end
