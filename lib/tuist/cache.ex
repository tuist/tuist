defmodule Tuist.Cache do
  @moduledoc ~S"""
  This module contains the [Nebulex](https://github.com/cabol/nebulex) configuration to add caching to Tuist.
  """
  use Nebulex.Cache,
    otp_app: :tuist,
    adapter: Nebulex.Adapters.Horde,
    horde: [
      members: :auto,
      process_redistribution: :passive
    ]

  def tuist do
    Application.fetch_env!(:tuist, :nebulex_cache)
  end

  def tuist(_mod, _fun, _args) do
    Application.fetch_env!(:tuist, :nebulex_cache)
  end
end
