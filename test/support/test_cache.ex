defmodule Tuist.TestCache do
  @moduledoc ~S"""
  This module contains the [Nebulex](https://github.com/cabol/nebulex) configuration to disable
  caching for testing purposes.
  """
  use Nebulex.Cache,
    otp_app: :tuist,
    adapter: Nebulex.Adapters.Nil
end
