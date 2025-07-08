defmodule TuistTestSupport do
  @moduledoc ~S"""
  This module acts as a boundary for all the testing utilities that we use in the tests.
  For now, the boundary checks are disabled, but we might want to declare and enforce some
  rules in the future.
  """
  use Boundary, check: [in: false, out: false]
end
