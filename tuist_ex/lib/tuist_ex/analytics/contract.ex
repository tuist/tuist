defmodule TuistEx.Analytics.Contract do
  @moduledoc false

  # Wire contract version the plugin was built against. Server accepts
  # unknown values; older clients may omit it entirely.
  @version "0.1"

  def version, do: @version
end
