defmodule Tuist.CLIVersions do
  @moduledoc """
  Canonical facts about CLI version support, shared by the deprecation warning
  (`TuistWeb.WarningsHeaderPlug`), the docs Compatibility page, and the
  backward-compatibility acceptance gate.

  This is a dependency-free leaf module on purpose: the docs loader expands it at
  compile time, so it must not pull in the web layer (which would create a
  compile-time cycle).
  """

  @minimum_supported_version "4.150.0"

  @doc """
  The oldest CLI version the server supports (a rolling ~3-month window).
  Clients below this receive a deprecation warning. Bump this value only.
  """
  def minimum_supported_version, do: @minimum_supported_version
end
